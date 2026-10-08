extends Node
## Google 登入（Autoload "GoogleAuth"）。
## 網頁版優先使用 FedCM（Google Identity Services One Tap，use_fedcm_for_prompt）：
## 不離開遊戲頁面，瀏覽器原生帳號選擇視窗取得 ID Token → POST 給伺服器驗證 → 重新載入。
## 瀏覽器不支援、載入失敗或驗證失敗時，自動退回 OAuth 重新導向流程。

const JS_SETUP := """
(function () {
  if (window.iqGoogleSignIn) return;
  function redirect() { window.location.href = '/api/auth/google/start?return=/'; }
  function loadGis(cb) {
    if (window.google && google.accounts && google.accounts.id) return cb();
    var s = document.createElement('script');
    s.src = 'https://accounts.google.com/gsi/client';
    s.async = true;
    s.onload = cb;
    s.onerror = redirect;
    document.head.appendChild(s);
  }
  window.iqGoogleSignIn = function (clientId) {
    loadGis(function () {
      fetch('/api/auth/google/nonce', { credentials: 'same-origin' })
        .then(function (r) { if (!r.ok) throw new Error('nonce'); return r.json(); })
        .then(function (d) {
          google.accounts.id.initialize({
            client_id: clientId,
            nonce: d.nonce,
            use_fedcm_for_prompt: true,
            auto_select: false,
            cancel_on_tap_outside: true,
            context: 'signin',
            callback: function (resp) {
              fetch('/api/auth/google/credential', {
                method: 'POST', credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ credential: resp.credential })
              }).then(function (r) { if (r.ok) window.location.reload(); else redirect(); }).catch(redirect);
            }
          });
          google.accounts.id.prompt(function (n) {
            // 非 FedCM 的舊版 One Tap 才有 isNotDisplayed；無法顯示時改走重新導向
            if (n && typeof n.isNotDisplayed === 'function' && n.isNotDisplayed()) redirect();
          });
        })
        .catch(redirect);
    });
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


## 退路：OAuth 重新導向（FedCM 被使用者關閉後冷卻期間，也可用這個）
func sign_in_redirect() -> void:
	var login_url: String = Net.base_url + "/api/auth/google/start?return=/"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href=%s" % JSON.stringify("/api/auth/google/start?return=/"), true)
	else:
		OS.shell_open(login_url)
