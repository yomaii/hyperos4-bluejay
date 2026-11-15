# Three DisplayFeatureManagerService methods that talk to Xiaomi's display HAL, replaced whole (tools/jar_smali.py).
#
# initWrapperLocked: looked up IDisplayFeature on every setScreenEffect while it was missing. Create a Wrapper
#   without a binder (the constructor skips both branches on null); its setFeature / registerCallback go to
#   PortDisplayBridge. setDimmingMode() is still called afterwards as in the original.
# initDisplayFeature: second lookup of the same HAL; now does nothing.
# notifyDisplayFeature: hand to PortDisplayBridge instead of transaction 7.

.method private initWrapperLocked()V
    .registers 4

    const-string v0, "DisplayFeatureManagerService"

    :try_start_0
    new-instance v1, Lcom/android/server/display/DisplayFeatureManagerService$DisplayFeatureManagerWrapper;

    const/4 v2, 0x0

    invoke-direct {v1, p0, v2}, Lcom/android/server/display/DisplayFeatureManagerService$DisplayFeatureManagerWrapper;-><init>(Lcom/android/server/display/DisplayFeatureManagerService;Ljava/lang/Object;)V

    iput-object v1, p0, Lcom/android/server/display/DisplayFeatureManagerService;->mWrapper:Lcom/android/server/display/DisplayFeatureManagerService$DisplayFeatureManagerWrapper;

    const-string v1, "initWrapperLocked: IDisplayFeature HAL replaced by PortDisplayBridge"

    invoke-static {v0, v1}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-direct {p0}, Lcom/android/server/display/DisplayFeatureManagerService;->setDimmingMode()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v1

    const-string v2, "initWrapperLocked failed"

    invoke-static {v0, v2, v1}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method

.method private initDisplayFeature()V
    .registers 1

    return-void
.end method

.method public notifyDisplayFeature(IIII)V
    .registers 5

    invoke-static {p1, p2, p3, p4}, Lcom/android/server/display/PortDisplayBridge;->notifyFeature(IIII)V

    return-void
.end method
