@tool
extends Node
## Google sign-in (Autoload "GoogleAuth").
## On web, prioritizes native FedCM (W3C Federated Credential Management API, Active / Button Mode):
## stays on the game page, browser natively pops up modal account chooser to obtain ID Token -> POST to server for verification -> reload.
## If the browser does not support FedCM (e.g. Safari, Firefox) or verification fails, automatically falls back to standard OAuth 2.0 redirect flow.

const JS_SETUP := """
(function () {
  if (window.iqGoogleSignIn) return;

  function redirect() {
    window.location.href = '/api/auth/google/start?return=/';
  }

  // True native FedCM flow (Active / Button Mode)
  async function runFedCM(clientId) {
    if (!('IdentityCredential' in window) || !navigator.credentials || !navigator.credentials.get) {
      return false;
    }

    // 1. First fetch secure nonce from server
    var nonceRes = await fetch('/api/auth/google/nonce', { credentials: 'same-origin' });
    if (!nonceRes.ok) throw new Error('nonce_fetch_failed');
    var nonceData = await nonceRes.json();
    var nonce = nonceData.nonce;

    // 2. Detect browser-supported FedCM mode (supports active or button)
    var mode = 'active';
    try {
      var modeSupported = false;
      await navigator.credentials.get({
        identity: Object.defineProperty({}, 'mode', {
          get: function () { modeSupported = true; }
        })
      }).catch(function () {});
      if (!modeSupported) mode = 'button';
    } catch (e) {
      mode = 'button';
    }

    // 3. Invoke browser native FedCM (call Google FedCM Provider directly)
    var cred = await navigator.credentials.get({
      identity: {
        context: 'signin',
        providers: [{
          configURL: 'https://accounts.google.com/gsi/fedcm.json',
          clientId: clientId,
          nonce: nonce,
          params: { nonce: nonce, response_type: 'id_token', scope: 'email profile openid' },
          fields: ['name', 'email', 'picture']
        }],
        mode: mode
      },
      mediation: 'required'
    });

    if (!cred || !cred.token) {
      throw new Error('no_token');
    }

    // Parse token returned by Google FedCM (may be JSON string {"id_token": "..."} or raw JWT)
    var rawToken = cred.token;
    var idToken = rawToken;
    if (typeof rawToken === 'string') {
      try {
        var parsed = JSON.parse(rawToken);
        if (parsed && typeof parsed === 'object') {
          idToken = parsed.id_token || parsed.token || parsed.credential || rawToken;
        }
      } catch (e) {
        idToken = rawToken;
      }
    } else if (rawToken && typeof rawToken === 'object') {
      idToken = rawToken.id_token || rawToken.token || rawToken.credential || '';
    }

    // 4. Submit ID Token to backend for verification and write session cookie
    var authRes = await fetch('/api/auth/google/credential', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ credential: idToken })
    });

    if (authRes.ok) {
      window.location.reload();
      return true;
    }
    var errText = await authRes.text().catch(function () { return ''; });
    console.error('Google credential verification failed:', authRes.status, errText);
    return false;
  }

  window.iqGoogleSignIn = async function (clientId) {
    try {
      var ok = await runFedCM(clientId);
      if (!ok) {
        console.warn('FedCM completed but verification was not successful, redirecting to OAuth...');
        redirect();
      }
    } catch (err) {
      console.warn('FedCM error:', err);
      // User manual cancellation (AbortError / cancelled dialog) stays on current screen without forced redirect
      if (err && (err.name === 'AbortError' || (err.name === 'NotAllowedError' && !String(err.message).toLowerCase().includes('disabled')))) {
        return;
      }
      // Other errors (e.g. browser restrictions, network failure) fall back to OAuth redirect flow
      redirect();
    }
  };
})();
"""


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS_SETUP, true)


## Google sign-in with FedCM priority
func sign_in() -> void:
	var client_id: String = str(Net.auth_config.get("googleClientId", "")) if Net.auth_config is Dictionary else ""
	if OS.has_feature("web") and client_id != "":
		JavaScriptBridge.eval("window.iqGoogleSignIn(%s)" % JSON.stringify(client_id), true)
	else:
		sign_in_redirect()


## Fallback: OAuth redirect flow (used on non-Chromium browsers or when FedCM fails)
func sign_in_redirect() -> void:
	var login_url: String = Net.base_url + "/api/auth/google/start?return=/"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href=%s" % JSON.stringify("/api/auth/google/start?return=/"), true)
	else:
		OS.shell_open(login_url)
