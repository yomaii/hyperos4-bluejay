.class final Lcom/android/systemui/biometrics/PortAodLongPress$Tap;
.super Landroid/hardware/TriggerEventListener;
.source "PortAodLongPress.java"

# AOD tap (com.google.sensor.single_touch, one-shot): with the screen off, call MiuiGxzwManager.notifyKeycodeGoto()
# to show the fingerprint icon for a few seconds. See PortAodLongPress.smali.


# instance fields
.field private final mPm:Landroid/os/PowerManager;

.field private final mSensor:Landroid/hardware/Sensor;

.field private final mSm:Landroid/hardware/SensorManager;


# direct methods
.method constructor <init>(Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;)V
    .registers 4

    invoke-direct {p0}, Landroid/hardware/TriggerEventListener;-><init>()V

    iput-object p1, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mSm:Landroid/hardware/SensorManager;

    iput-object p2, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mSensor:Landroid/hardware/Sensor;

    iput-object p3, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mPm:Landroid/os/PowerManager;

    return-void
.end method


# virtual methods
.method public onTrigger(Landroid/hardware/TriggerEvent;)V
    .registers 5

    :try_start_0
    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mSm:Landroid/hardware/SensorManager;

    iget-object v1, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mSensor:Landroid/hardware/Sensor;

    invoke-virtual {v0, p0, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;->mPm:Landroid/os/PowerManager;

    invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z

    move-result v0

    if-nez v0, :goto_ret

    invoke-static {}, Lcom/miui/keyguard/biometrics/fod/MiuiFingerPrintFactory;->getFingerPrintManager()Lcom/miui/keyguard/biometrics/fod/IFingerPrintManager;

    move-result-object v0

    instance-of v1, v0, Lcom/miui/keyguard/biometrics/fod/MiuiGxzwManager;

    if-eqz v1, :goto_ret

    check-cast v0, Lcom/miui/keyguard/biometrics/fod/MiuiGxzwManager;

    const-string v1, "PortAodLongPress"

    const-string v2, "tap: show fingerprint icon"

    invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {v0}, Lcom/miui/keyguard/biometrics/fod/MiuiGxzwManager;->notifyKeycodeGoto()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :goto_ret
    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortAodLongPress"

    const-string v2, "tap failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method
