package com.glclash.app

import android.app.Application
import android.content.Context
import com.glclash.app.common.GlobalState

class GLClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
