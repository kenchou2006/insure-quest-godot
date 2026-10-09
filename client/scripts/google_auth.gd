@tool
extends Node
## Google 登入（Autoload "GoogleAuth"）。
## 網頁版優先使用原生 FedCM（W3C Federated Credential Management API，Active / Button Mode）：
## 不離開遊戲頁面，瀏覽器原生彈出強制帳號選擇視窗取得 ID Token → POST 給伺服器驗證 → 重新載入。
## 若瀏覽器不支援 FedCM（如 Safari、Firefox）或驗證失敗，自動退回標準 OAuth 2.0 重新導向流程。

const JS_SETUP := """
(function () {
  if (window.iqGoogleSignIn) return;

  function redirect() {
    window.location.href = '/api/auth/google/start?return=/';
  }

  // 真正的原生 FedCM 流程（Active / Button Mode）
  async function runFedCM(clientId) {
    if (!('IdentityCredential' in window) || !navigator.credentials || !navigator.credentials.get) {
      return false;
    }

    // 1. 先向伺服器取得安全 nonce
    var nonceRes = await fetch('/api/auth/google/nonce', { credentials: 'same-origin' });
    if (!nonceRes.ok) throw new Error('nonce_fetch_failed');
    var nonceData = await nonceRes.json();
    var nonce = nonceData.nonce;

    // 2. 檢測瀏覽器支援的 FedCM 模式（支援 active 或 button）
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

    // 3. 呼叫瀏覽器原生 FedCM（直接呼叫 Google FedCM Provider）
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

    // 解析 Google FedCM 回傳的 token（可能為 JSON 字串 {"id_token": "..."} 或直接為 JWT）
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

    // 4. 將 ID Token 送交後端驗證並寫入工作階段 Cookie
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
      // 使用者手動取消 (AbortError / 取消對話框) 則停留在原畫面，不強制跳轉
      if (err && (err.name === 'AbortError' || (err.name === 'NotAllowedError' && !String(err.message).toLowerCase().includes('disabled')))) {
        return;
      }
      // 其他錯誤（如瀏覽器限制、網路失敗等）則退回 OAuth 重新導向流程
      redirect();
    }
  };
})();
"""


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS_SETUP, true)


## FedCM 優先的 Google 登入
func sign_in() -> void:
	var client_id: String = str(Net.auth_config.get("googleClientId", "")) if Net.auth_config is Dictionary else ""
	if OS.has_feature("web") and client_id != "":
		JavaScriptBridge.eval("window.iqGoogleSignIn(%s)" % JSON.stringify(client_id), true)
	else:
		sign_in_redirect()


## 退路：OAuth 重新導向流程（非 Chromium 瀏覽器或 FedCM 失敗時使用）
func sign_in_redirect() -> void:
	var login_url: String = Net.base_url + "/api/auth/google/start?return=/"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href=%s" % JSON.stringify("/api/auth/google/start?return=/"), true)
	else:
		OS.shell_open(login_url)
