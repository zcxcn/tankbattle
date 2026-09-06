package com.ironembers.game;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.WindowManager;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.webkit.WebViewAssetLoader;
import java.io.ByteArrayInputStream;
import java.util.Collections;

/** Offline, GPU-accelerated container. Standard mouse/gamepad events go straight to Chromium. */
public final class MainActivity extends Activity {
    private static final String ORIGIN = "https://appassets.androidplatform.net";
    private WebView web;
    private PowerManager power;
    private boolean background = true;
    private boolean pageReady = false;
    private PowerManager.OnThermalStatusChangedListener thermalListener;
    private final BroadcastReceiver batteryReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { pushState(); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        power = (PowerManager) getSystemService(POWER_SERVICE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams attrs = getWindow().getAttributes();
            attrs.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            getWindow().setAttributes(attrs);
        }
        WindowManager.LayoutParams display = getWindow().getAttributes();
        display.preferredRefreshRate = 60f;
        getWindow().setAttributes(display);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(19, 29, 21));
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);
        web.setOverScrollMode(WebView.OVER_SCROLL_NEVER);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setUserAgentString(settings.getUserAgentString() + " IronEmbersAndroid/1.0");
        WebView.setWebContentsDebuggingEnabled(false);
        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/", new WebViewAssetLoader.AssetsPathHandler(this)).build();
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("https".equals(uri.getScheme()) && "appassets.androidplatform.net".equals(uri.getHost())) {
                    Uri asset = "/".equals(uri.getPath()) ? Uri.parse(ORIGIN + "/index.html") : uri;
                    WebResourceResponse response = loader.shouldInterceptRequest(asset);
                    if (response != null) return response;
                }
                return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("https".equals(uri.getScheme()) && "appassets.androidplatform.net".equals(uri.getHost())) {
                    if ("/".equals(uri.getPath())) { view.loadUrl(ORIGIN + "/index.html"); return true; }
                    return false;
                }
                return true;
            }
            @Override public void onPageFinished(WebView view, String url) {
                pageReady = true; pushState(); view.requestFocus();
            }
        });
        setContentView(web);
        immersive();
        if (Build.VERSION.SDK_INT >= 29) {
            thermalListener = status -> runOnUiThread(this::pushState);
            power.addThermalStatusListener(getMainExecutor(), thermalListener);
        }
        IntentFilter filter = new IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(batteryReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(batteryReceiver, filter);
        web.loadUrl(ORIGIN + "/index.html");
    }

    private void immersive() {
        WindowInsetsControllerCompat controller = WindowCompat.getInsetsController(getWindow(), web);
        controller.hide(WindowInsetsCompat.Type.systemBars());
        controller.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }
    private String stateScript() {
        int thermal = Build.VERSION.SDK_INT >= 29 ? power.getCurrentThermalStatus() : 0;
        return "window.dispatchEvent(new CustomEvent('tank-native-update',{detail:{thermal:" + thermal
                + ",powerSave:" + power.isPowerSaveMode() + ",background:" + background + "}}));";
    }
    private void pushState() { if (web != null && pageReady) web.evaluateJavascript(stateScript(), null); }
    @Override protected void onPause() {
        background = true;
        if (web != null) {
            // Deliver pause/clear-input/audio suspension before stopping JS timers.
            web.evaluateJavascript(stateScript(), ignored -> {
                if (background && web != null) { web.onPause(); web.pauseTimers(); }
            });
        }
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        super.onPause();
    }
    @Override protected void onResume() {
        super.onResume(); background = false;
        if (web != null) { web.onResume(); web.resumeTimers(); web.requestFocus(); immersive(); pushState(); }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        if (focused && web != null) immersive();
    }
    @Override public void onBackPressed() {
        if (web != null) web.evaluateJavascript("window.dispatchEvent(new Event('tank-native-back'));", null);
    }
    @Override protected void onDestroy() {
        unregisterReceiver(batteryReceiver);
        if (Build.VERSION.SDK_INT >= 29 && thermalListener != null) power.removeThermalStatusListener(thermalListener);
        if (web != null) { web.stopLoading(); web.destroy(); web = null; }
        super.onDestroy();
    }
}
