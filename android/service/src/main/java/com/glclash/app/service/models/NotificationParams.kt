package com.glclash.app.service.models

data class NotificationParams(
    val title: String = "GLClash",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)
