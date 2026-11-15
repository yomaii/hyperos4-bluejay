# DisplayFeatureManagerService$DisplayFeatureManagerWrapper: calls that went to Xiaomi's display HAL through
# callBinderTransact / callHwBinderTransact go to PortDisplayBridge. Method headers must match the original.

.method setFeature(IIII)V
    .registers 5

    invoke-static {p1, p2, p3, p4}, Lcom/android/server/display/PortDisplayBridge;->setFeature(IIII)V

    return-void
.end method

.method registerCallback(ILjava/lang/Object;)V
    .registers 3

    invoke-static {p1, p2}, Lcom/android/server/display/PortDisplayBridge;->registerCallback(ILjava/lang/Object;)V

    return-void
.end method
