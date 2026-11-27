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
 * 仅在从「闪雀」主动拉起支付宝后的短暂窗口期（默认 10 秒）内生效的无障碍跳广告服务：
 * - 仅监听支付宝包名 (com.eg.android.AlipayGphone)
 * - 集成四重策略：
 *   1. 常规文本/描述匹配（「跳过」按钮，覆盖支付宝主 App 开屏广告）
 *   2. GKD 规则 1：小程序开屏广告无文本无 ID 的匿名跳过 View
 *   3. GKD 规则 2：XRiverActivity 顶部开屏广告栏坐标点击（left = width * 0.2490, top = width * 0.0435）
 *   4. 视觉锚点兜底：检测到「精选推荐」/倒计时「N秒」且未进入充电页时，结合顶部胶囊纵坐标或「广告」/「N秒」锚点点击「跳过」
 * - 窗口期外完全不遍历节点树，零后台耗电
 */
class AlipayAdSkipService : AccessibilityService() {

    companion object {
        private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
        private const val MIN_CLICK_INTERVAL_MS = 500L
        private const val MAX_CLICKS_PER_WINDOW = 3
        private val COUNTDOWN_REGEX = Regex("^[1-5]秒$")
        private val CHARGING_PAGE_KEYWORDS = listOf(
            "立即充电",
            "确认支付",
            "充电时长",
            "选择充电",
            "选插座",
            "充满自停",
            "开始充电",
        )

        @Volatile
        private var armedUntilElapsedMs: Long = 0L

        @Volatile
        private var clicksInWindow: Int = 0

        @Volatile
        private var lastClickElapsedMs: Long = 0L

        @Volatile
        private var currentActivityClass: String = ""

        fun armWindow(durationMs: Long = 10000L) {
            armedUntilElapsedMs = SystemClock.elapsedRealtime() + durationMs
            clicksInWindow = 0
            currentActivityClass = ""
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

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val cls = event.className?.toString().orEmpty()
            if (cls.contains('.') &&
                !cls.startsWith("android.widget.") &&
                !cls.startsWith("android.view.")
            ) {
                currentActivityClass = cls
            }
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastClickElapsedMs < MIN_CLICK_INTERVAL_MS) return

        val roots = collectAlipayRoots()
        if (roots.isEmpty()) return

        for (root in roots) {
            try {
                if (trySkipInRoot(root)) {
                    lastClickElapsedMs = now
                    clicksInWindow++
                    if (clicksInWindow >= MAX_CLICKS_PER_WINDOW) {
                        armedUntilElapsedMs = 0L
                    }
                    return
                }
            } catch (_: Exception) {
                // 节点在遍历期间被销毁时静默忽略
            }
        }
    }

    override fun onInterrupt() {
        // 无需额外清理
    }

    private fun collectAlipayRoots(): List<AccessibilityNodeInfo> {
        val result = ArrayList<AccessibilityNodeInfo>(3)
        val active = rootInActiveWindow
        if (active != null && active.packageName?.toString() == ALIPAY_PACKAGE) {
            result.add(active)
        }
        try {
            val allWindows = windows
            if (allWindows != null) {
                for (window in allWindows) {
                    val root = window.root ?: continue
                    if (root.packageName?.toString() == ALIPAY_PACKAGE &&
                        result.none { it == root }
                    ) {
                        result.add(root)
                    }
                }
            }
        } catch (_: Exception) {
            // 忽略多窗口访问异常
        }
        return result
    }

    private fun trySkipInRoot(root: AccessibilityNodeInfo): Boolean {
        // 策略 1：标准「跳过」文本/描述按钮（主 App 开屏与标准开屏）
        val textSkipNode = findSkipNodeByText(root)
        if (textSkipNode != null && clickNodeOrGesture(textSkipNode)) {
            return true
        }

        // 若已经进入充电/支付页面，禁止执行无文本结构或坐标点击，彻底防止误触
        if (isChargingPageLoaded(root)) {
            return false
        }

        val isMiniProgramActivity = currentActivityClass.contains("XRiverActivity") ||
            currentActivityClass.contains("NebulaActivity") ||
            currentActivityClass.contains("H5Activity")

        // 策略 2：GKD 规则 1（小程序开屏广告：无 id、无 text 的叶子 View 位于父容器末尾）
        val gkdRule1Node = findGkdMiniProgramSkipNode(root)
        if (gkdRule1Node != null && clickNodeOrGesture(gkdRule1Node)) {
            return true
        }

        // 策略 3：GKD 规则 2（XRiverActivity 顶部全宽开屏广告栏坐标点击）
        if (tryGkdRule2CoordinateClick(root, isMiniProgramActivity)) {
            return true
        }

        // 策略 4：视觉锚点兜底（页面出现「精选推荐」或顶部倒计时「N秒」）
        if (tryVisualAnchorSkip(root)) {
            return true
        }

        return false
    }

    // -------------------------------------------------------------------------
    // 策略 1：文本 / contentDescription 匹配「跳过」
    // -------------------------------------------------------------------------

    private fun findSkipNodeByText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val byText = root.findAccessibilityNodeInfosByText("跳过")
        if (!byText.isNullOrEmpty()) {
            for (node in byText) {
                if (isLikelySkipButton(node)) {
                    return node
                }
            }
        }
        return dfsFindSkipByText(root, 0)
    }

    private fun dfsFindSkipByText(node: AccessibilityNodeInfo?, depth: Int): AccessibilityNodeInfo? {
        if (node == null || depth > 14) return null
        if (isLikelySkipButton(node)) return node
        for (i in 0 until node.childCount) {
            val found = dfsFindSkipByText(node.getChild(i), depth + 1)
            if (found != null) return found
        }
        return null
    }

    private fun isLikelySkipButton(node: AccessibilityNodeInfo): Boolean {
        if (!node.isVisibleToUser) return false
        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        val label = if (text.isNotEmpty()) text else desc
        if (label.isEmpty() || label.length > 10) return false
        if (!label.contains("跳过")) return false

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.width() <= 0 || rect.height() <= 0) return false
        val screenHeight = resources.displayMetrics.heightPixels
        return rect.top < screenHeight * 0.45f
    }

    // -------------------------------------------------------------------------
    // 策略 2：GKD key:24 规则 1
    // @View[id=null][text=null][childCount=0][visibleToUser=true]
    //   < ViewGroup[id=null][text=null][childCount=1][index=parent.childCount-1]
    //   <... < [id="android:id/content"]
    // -------------------------------------------------------------------------

    private fun findGkdMiniProgramSkipNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val contents = root.findAccessibilityNodeInfosByViewId("android:id/content")
        val searchRoots = if (!contents.isNullOrEmpty()) contents else listOf(root)
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels

        for (content in searchRoots) {
            val found = dfsFindGkdRule1(content, 0, screenWidth, screenHeight)
            if (found != null) return found
        }
        return null
    }

    private fun dfsFindGkdRule1(
        node: AccessibilityNodeInfo?,
        depth: Int,
        screenWidth: Int,
        screenHeight: Int,
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 18) return null

        val cls = node.className?.toString().orEmpty()
        if (depth >= 7 &&
            cls.endsWith(".View") &&
            node.viewIdResourceName == null &&
            node.text == null &&
            node.childCount == 0 &&
            node.isVisibleToUser
        ) {
            val parent = node.parent
            if (parent != null &&
                parent.viewIdResourceName == null &&
                parent.text == null &&
                parent.childCount == 1 &&
                isLastChildOfParent(parent)
            ) {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                // 跳过胶囊位于左上区域，严禁触碰右上角小程序关闭胶囊 (x > 65%)
                if (rect.top in 1..(screenHeight * 0.22f).toInt() &&
                    rect.right < (screenWidth * 0.65f).toInt() &&
                    rect.width() in 36..(screenWidth * 0.42f).toInt() &&
                    rect.height() in 24..180
                ) {
                    return node
                }
            }
        }

        for (i in 0 until node.childCount) {
            val found = dfsFindGkdRule1(node.getChild(i), depth + 1, screenWidth, screenHeight)
            if (found != null) return found
        }
        return null
    }

    private fun isLastChildOfParent(node: AccessibilityNodeInfo): Boolean {
        val grandParent = node.parent ?: return false
        val count = grandParent.childCount
        if (count <= 0) return false
        val lastChild = grandParent.getChild(count - 1) ?: return false
        return lastChild == node
    }

    // -------------------------------------------------------------------------
    // 策略 3：GKD key:24 规则 2（XRiverActivity 顶部开屏广告栏坐标点击）
    // position: { left: 'width * 0.2490', top: 'width * 0.0435' }
    // -------------------------------------------------------------------------

    private fun tryGkdRule2CoordinateClick(
        root: AccessibilityNodeInfo,
        isMiniProgramActivity: Boolean,
    ): Boolean {
        val contents = root.findAccessibilityNodeInfosByViewId("android:id/content")
        if (contents.isNullOrEmpty()) return false

        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels

        for (content in contents) {
            // 规则 2 要求 android:id/content 有 2 个子节点（第 2 个为开屏广告覆盖层）
            // 或者当前已确认处于 XRiverActivity 且存在开屏广告特征
            val overlayLayer = when {
                content.childCount == 2 -> content.getChild(1)
                isMiniProgramActivity && content.childCount >= 2 -> content.getChild(content.childCount - 1)
                else -> null
            } ?: continue

            val headerBar = findGkdRule2HeaderBar(overlayLayer, 0, screenWidth, screenHeight)
            if (headerBar != null) {
                val rect = Rect()
                headerBar.getBoundsInScreen(rect)
                val tapX = rect.left + rect.width() * 0.2490f
                val tapY = (rect.top + rect.width() * 0.0435f)
                    .coerceIn(rect.top + 8f, rect.bottom - 8f)
                if (dispatchTap(tapX, tapY)) {
                    return true
                }
            }
        }
        return false
    }

    private fun findGkdRule2HeaderBar(
        node: AccessibilityNodeInfo?,
        depth: Int,
        screenWidth: Int,
        screenHeight: Int,
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 8) return null

        val parent = node.parent
        if (node.isVisibleToUser &&
            node.childCount == 1 &&
            parent != null &&
            parent.childCount > 3
        ) {
            val child0 = node.getChild(0)
            val childCls = child0?.className?.toString().orEmpty()
            if (childCls.endsWith(".View")) {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                if (rect.height() in 30..180 &&
                    rect.width() >= (screenWidth * 0.85f).toInt() &&
                    rect.top in 0..(screenHeight * 0.16f).toInt()
                ) {
                    return node
                }
            }
        }

        for (i in 0 until node.childCount) {
            val found = findGkdRule2HeaderBar(node.getChild(i), depth + 1, screenWidth, screenHeight)
            if (found != null) return found
        }
        return null
    }

    // -------------------------------------------------------------------------
    // 策略 4：视觉锚点兜底（仅当明确看到「精选推荐」或顶部倒计时「N秒」）
    // -------------------------------------------------------------------------

    private fun tryVisualAnchorSkip(root: AccessibilityNodeInfo): Boolean {
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels

        val hasFeaturedTitle = hasVisibleText(root, "精选推荐")
        val countdownNode = findTopCountdownNode(root, 0, screenWidth, screenHeight)

        if (!hasFeaturedTitle && countdownNode == null) {
            return false
        }

        // 4a. 若找到顶部倒计时「2秒」节点，其正左侧就是「跳过」
        if (countdownNode != null) {
            val rect = Rect()
            countdownNode.getBoundsInScreen(rect)
            val tapX = (rect.left - screenWidth * 0.075f)
                .coerceIn(screenWidth * 0.19f, screenWidth * 0.30f)
            val tapY = rect.exactCenterY()
            if (dispatchTap(tapX, tapY)) {
                return true
            }
        }

        // 4b. 若找到顶部左侧「广告」节点，其正右侧就是「跳过」
        val adNodes = root.findAccessibilityNodeInfosByText("广告")
        if (!adNodes.isNullOrEmpty()) {
            for (adNode in adNodes) {
                if (!adNode.isVisibleToUser) continue
                val rect = Rect()
                adNode.getBoundsInScreen(rect)
                if (rect.top in 1..(screenHeight * 0.20f).toInt() &&
                    rect.left < (screenWidth * 0.25f).toInt() &&
                    rect.height() in 20..160
                ) {
                    val tapX = (rect.right + screenWidth * 0.065f)
                        .coerceIn(screenWidth * 0.20f, screenWidth * 0.31f)
                    val tapY = rect.exactCenterY()
                    if (dispatchTap(tapX, tapY)) {
                        return true
                    }
                }
            }
        }

        // 4c. 若确认出现「精选推荐」，借用右上角小程序胶囊（「更多」/「关闭」）的精确 Y 坐标，
        //     配合左上角「跳过」固定横坐标 (width * 0.2490) 点击
        if (hasFeaturedTitle) {
            val capsuleY = findMiniProgramCapsuleCenterY(root, 0, screenHeight)
            if (capsuleY != null) {
                val tapX = screenWidth * 0.2490f
                if (dispatchTap(tapX, capsuleY)) {
                    return true
                }
            }
        }

        return false
    }

    private fun findTopCountdownNode(
        node: AccessibilityNodeInfo?,
        depth: Int,
        screenWidth: Int,
        screenHeight: Int,
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 14) return null
        if (node.isVisibleToUser) {
            val text = node.text?.toString()?.trim().orEmpty()
            if (text.length in 2..3 && COUNTDOWN_REGEX.matches(text)) {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                if (rect.top in 1..(screenHeight * 0.20f).toInt() &&
                    rect.left < (screenWidth * 0.50f).toInt()
                ) {
                    return node
                }
            }
        }
        for (i in 0 until node.childCount) {
            val found = findTopCountdownNode(node.getChild(i), depth + 1, screenWidth, screenHeight)
            if (found != null) return found
        }
        return null
    }

    private fun findMiniProgramCapsuleCenterY(
        node: AccessibilityNodeInfo?,
        depth: Int,
        screenHeight: Int,
    ): Float? {
        if (node == null || depth > 12) return null
        if (node.isVisibleToUser) {
            val desc = node.contentDescription?.toString()?.trim().orEmpty()
            if (desc == "更多" || desc == "关闭" || desc == "关闭小程序") {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                if (rect.top in 1..(screenHeight * 0.16f).toInt() && rect.height() in 24..160) {
                    return rect.exactCenterY()
                }
            }
        }
        for (i in 0 until node.childCount) {
            val found = findMiniProgramCapsuleCenterY(node.getChild(i), depth + 1, screenHeight)
            if (found != null) return found
        }
        return null
    }

    private fun isChargingPageLoaded(root: AccessibilityNodeInfo): Boolean {
        for (keyword in CHARGING_PAGE_KEYWORDS) {
            if (hasVisibleText(root, keyword)) {
                return true
            }
        }
        return false
    }

    private fun hasVisibleText(root: AccessibilityNodeInfo, query: String): Boolean {
        val nodes = root.findAccessibilityNodeInfosByText(query)
        if (nodes.isNullOrEmpty()) return false
        return nodes.any { it.isVisibleToUser }
    }

    // -------------------------------------------------------------------------
    // 点击与手势执行
    // -------------------------------------------------------------------------

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

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.width() > 0 && rect.height() > 0) {
            return dispatchTap(rect.exactCenterX(), rect.exactCenterY())
        }
        return false
    }

    private fun dispatchTap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        if (x <= 0f || y <= 0f) return false
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, 60L))
            .build()
        return dispatchGesture(gesture, null, null)
    }
}
