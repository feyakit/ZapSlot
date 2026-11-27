package com.feyakit.charge_quick

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 仅在从「闪雀」主动拉起支付宝后的短暂窗口期（默认 6 秒）内生效的无障碍跳广告服务：
 * - 仅监听支付宝包名 (com.eg.android.AlipayGphone)
 * - 仅匹配文本/描述包含「跳过」且长度 <= 10 的按钮节点，防止误触其他页面按钮
 * - 优先执行 ACTION_CLICK，若节点不可直接点击则退回坐标手势点击
 * - 窗口期外完全不遍历节点树，零后台耗电
 */
class AlipayAdSkipService : AccessibilityService() {

    companion object {
        private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
        private const val MIN_CLICK_INTERVAL_MS = 450L
        private const val MAX_CLICKS_PER_WINDOW = 2

        @Volatile
        private var armedUntilElapsedMs: Long = 0L

        @Volatile
        private var clicksInWindow: Int = 0

        @Volatile
        private var lastClickElapsedMs: Long = 0L

        fun armWindow(durationMs: Long = 6000L) {
            armedUntilElapsedMs = SystemClock.elapsedRealtime() + durationMs
            clicksInWindow = 0
        }

        private fun isArmed(): Boolean {
            val now = SystemClock.elapsedRealtime()
            return now <= armedUntilElapsedMs && clicksInWindow < MAX_CLICKS_PER_WINDOW
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isArmed()) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg != ALIPAY_PACKAGE) return

        val now = SystemClock.elapsedRealtime()
        if (now - lastClickElapsedMs < MIN_CLICK_INTERVAL_MS) return

        val root = rootInActiveWindow ?: return
        try {
            val target = findSkipNode(root) ?: return
            if (clickNodeOrGesture(target)) {
                lastClickElapsedMs = now
                clicksInWindow++
                if (clicksInWindow >= MAX_CLICKS_PER_WINDOW) {
                    armedUntilElapsedMs = 0L
                }
            }
        } catch (_: Exception) {
            // 节点在遍历期间被销毁时静默忽略
        }
    }

    override fun onInterrupt() {
        // 无需额外清理
    }

    private fun findSkipNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // 1. 优先使用系统快速文本查找
        val byText = root.findAccessibilityNodeInfosByText("跳过")
        if (!byText.isNullOrEmpty()) {
            for (node in byText) {
                if (isLikelySkipButton(node)) {
                    return node
                }
            }
        }

        // 2. 兜底遍历（适配仅设置在 contentDescription 上的自定义控件）
        return dfsFindSkip(root, 0)
    }

    private fun dfsFindSkip(node: AccessibilityNodeInfo?, depth: Int): AccessibilityNodeInfo? {
        if (node == null || depth > 14) return null
        if (isLikelySkipButton(node)) return node
        for (i in 0 until node.childCount) {
            val found = dfsFindSkip(node.getChild(i), depth + 1)
            if (found != null) return found
        }
        return null
    }

    private fun isLikelySkipButton(node: AccessibilityNodeInfo): Boolean {
        if (!node.isVisibleToUser) return false
        val text = node.text?.toString()?.trim() ?: ""
        val desc = node.contentDescription?.toString()?.trim() ?: ""
        val label = if (text.isNotEmpty()) text else desc
        if (label.isEmpty() || label.length > 10) return false
        if (!label.contains("跳过")) return false

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.width() <= 0 || rect.height() <= 0) return false
        // 支付宝开屏广告的“跳过”胶囊位于屏幕上半区，过滤底部误匹配
        val screenHeight = resources.displayMetrics.heightPixels
        return rect.top < screenHeight * 0.45f
    }

    private fun clickNodeOrGesture(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        var hops = 0
        while (current != null && hops < 4) {
            if (current.isClickable && current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
            current = current.parent
            hops++
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            if (rect.width() > 0 && rect.height() > 0) {
                val cx = rect.exactCenterX()
                val cy = rect.exactCenterY()
                val path = Path().apply { moveTo(cx, cy) }
                val gesture = GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0L, 60L))
                    .build()
                return dispatchGesture(gesture, null, null)
            }
        }
        return false
    }
}
