# HyperOS power-saving / performance modes -> Pixel Power HAL hints (see port_perf.rc).
# Added to services.jar; started from PowerManagerService.onBootPhase(500) after systemReady() (onBootPhase.insert).
#
# Java equivalent:
#   static void start(Context c) {
#     PortPerfHint.start(c);
#     try { HandlerThread t = new HandlerThread("PortPerfBridge"); t.start();
#           Handler h = new Handler(t.getLooper()); ContentResolver cr = c.getContentResolver();
#           PortPerfBridge b = new PortPerfBridge(h, cr);
#           for (k : {power_supersave_mode_open, POWER_SAVE_MODE_OPEN, POWER_PERFORMANCE_MODE_OPEN})
#             cr.registerContentObserver(Settings.System.getUriFor(k), false, b);
#           c.registerReceiver(new PortPerfScreen(b), new IntentFilter(Intent.ACTION_SCREEN_ON), null, h);
#           h.post(b);
#     } catch (Throwable e) { Slog.e(TAG, "start failed", e); }
#   }
#   mode(): super / save / perf / balance, checking power_supersave_mode_open, POWER_SAVE_MODE_OPEN, POWER_PERFORMANCE_MODE_OPEN
#   apply(): setprop sys.port.perfmode <mode> when it changed
#   onChange(): apply()
#   run(): apply(); setprop sys.port.perfmode.tick <n+1> (init re-sends the hint, which expires after an hour);
#          reschedule in 50 minutes. PortPerfScreen also calls run() on screen on, since the hints expire in real
#          time while the Handler timer stops in deep sleep.
# Every entry point catches Throwable and only logs.

.class public final Lcom/android/server/power/PortPerfBridge;
.super Landroid/database/ContentObserver;
.source "PortPerfBridge.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field private final mCr:Landroid/content/ContentResolver;

.field private final mHandler:Landroid/os/Handler;

.field private mLast:Ljava/lang/String;

.field private mTick:I


# direct methods
.method private constructor <init>(Landroid/os/Handler;Landroid/content/ContentResolver;)V
    .registers 3

    invoke-direct {p0, p1}, Landroid/database/ContentObserver;-><init>(Landroid/os/Handler;)V

    iput-object p1, p0, Lcom/android/server/power/PortPerfBridge;->mHandler:Landroid/os/Handler;

    iput-object p2, p0, Lcom/android/server/power/PortPerfBridge;->mCr:Landroid/content/ContentResolver;

    return-void
.end method

.method public static start(Landroid/content/Context;)V
    .registers 8

    # PortPerfHint catches its own exceptions
    invoke-static {p0}, Lcom/android/server/power/PortPerfHint;->start(Landroid/content/Context;)V

    :try_start_0
    new-instance v0, Landroid/os/HandlerThread;

    const-string v1, "PortPerfBridge"

    invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V

    invoke-virtual {v0}, Landroid/os/HandlerThread;->start()V

    new-instance v1, Landroid/os/Handler;

    invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;

    move-result-object v0

    invoke-direct {v1, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v2

    new-instance v0, Lcom/android/server/power/PortPerfBridge;

    invoke-direct {v0, v1, v2}, Lcom/android/server/power/PortPerfBridge;-><init>(Landroid/os/Handler;Landroid/content/ContentResolver;)V

    const/4 v3, 0x0

    const-string v4, "power_supersave_mode_open"

    invoke-static {v4}, Landroid/provider/Settings$System;->getUriFor(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v4

    invoke-virtual {v2, v4, v3, v0}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V

    const-string v4, "POWER_SAVE_MODE_OPEN"

    invoke-static {v4}, Landroid/provider/Settings$System;->getUriFor(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v4

    invoke-virtual {v2, v4, v3, v0}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V

    const-string v4, "POWER_PERFORMANCE_MODE_OPEN"

    invoke-static {v4}, Landroid/provider/Settings$System;->getUriFor(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v4

    invoke-virtual {v2, v4, v3, v0}, Landroid/content/ContentResolver;->registerContentObserver(Landroid/net/Uri;ZLandroid/database/ContentObserver;)V

    new-instance v5, Lcom/android/server/power/PortPerfScreen;

    invoke-direct {v5, v0}, Lcom/android/server/power/PortPerfScreen;-><init>(Lcom/android/server/power/PortPerfBridge;)V

    new-instance v6, Landroid/content/IntentFilter;

    const-string v4, "android.intent.action.SCREEN_ON"

    invoke-direct {v6, v4}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V

    const/4 v4, 0x0

    invoke-virtual {p0, v5, v6, v4, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;)Landroid/content/Intent;

    invoke-virtual {v1, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    const-string v0, "PortPerfBridge"

    const-string v1, "started"

    invoke-static {v0, v1}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortPerfBridge"

    const-string v2, "start failed"

    invoke-static {v1, v2, v0}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method

.method private mode()Ljava/lang/String;
    .registers 5

    iget-object v0, p0, Lcom/android/server/power/PortPerfBridge;->mCr:Landroid/content/ContentResolver;

    const/4 v1, 0x0

    const/4 v3, 0x1

    const-string v2, "power_supersave_mode_open"

    invoke-static {v0, v2, v1}, Landroid/provider/Settings$System;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v2

    if-ne v2, v3, :cond_save

    const-string v2, "super"

    return-object v2

    :cond_save
    const-string v2, "POWER_SAVE_MODE_OPEN"

    invoke-static {v0, v2, v1}, Landroid/provider/Settings$System;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v2

    if-ne v2, v3, :cond_perf

    const-string v2, "save"

    return-object v2

    :cond_perf
    const-string v2, "POWER_PERFORMANCE_MODE_OPEN"

    invoke-static {v0, v2, v1}, Landroid/provider/Settings$System;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v2

    if-ne v2, v3, :cond_balance

    const-string v2, "perf"

    return-object v2

    :cond_balance
    const-string v2, "balance"

    return-object v2
.end method

.method private apply()V
    .registers 4

    :try_start_0
    invoke-direct {p0}, Lcom/android/server/power/PortPerfBridge;->mode()Ljava/lang/String;

    move-result-object v0

    iget-object v1, p0, Lcom/android/server/power/PortPerfBridge;->mLast:Ljava/lang/String;

    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_same

    iput-object v0, p0, Lcom/android/server/power/PortPerfBridge;->mLast:Ljava/lang/String;

    const-string v1, "sys.port.perfmode"

    invoke-static {v1, v0}, Landroid/os/SystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V

    const-string v1, "PortPerfBridge"

    const-string v2, "mode -> "

    invoke-virtual {v2, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v2

    invoke-static {v1, v2}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I

    :cond_same
    nop
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortPerfBridge"

    const-string v2, "apply failed"

    invoke-static {v1, v2, v0}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method


# virtual methods
.method public onChange(Z)V
    .registers 2

    invoke-direct {p0}, Lcom/android/server/power/PortPerfBridge;->apply()V

    return-void
.end method

.method public run()V
    .registers 5

    invoke-direct {p0}, Lcom/android/server/power/PortPerfBridge;->apply()V

    :try_start_0
    iget v0, p0, Lcom/android/server/power/PortPerfBridge;->mTick:I

    add-int/lit8 v0, v0, 0x1

    iput v0, p0, Lcom/android/server/power/PortPerfBridge;->mTick:I

    invoke-static {v0}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;

    move-result-object v0

    const-string v1, "sys.port.perfmode.tick"

    invoke-static {v1, v0}, Landroid/os/SystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V

    iget-object v0, p0, Lcom/android/server/power/PortPerfBridge;->mHandler:Landroid/os/Handler;

    # drop the pending run, keep one timer
    invoke-virtual {v0, p0}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V

    # 50 minutes
    const-wide/32 v1, 0x2dc6c0

    invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortPerfBridge"

    const-string v2, "tick failed"

    invoke-static {v1, v2, v0}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method
