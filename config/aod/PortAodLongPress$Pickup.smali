.class final Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;
.super Landroid/hardware/TriggerEventListener;
.source "PortAodLongPress.java"

# Lift to wake: android.sensor.pick_up_gesture (type 25, wake-up, one-shot). Xiaomi's KeyguardSensorInjector only
# knows its own continuous sensor 33171036. A trigger sensor needs requestTriggerSensor, re-armed after each event.
# On trigger, with System pick_up_gesture_wakeup_mode == 1 and the screen off, wake up with WAKE_REASON_LIFT (16)
# and "com.android.systemui:PICK_UP" like Xiaomi's keyguard. Put-down-to-sleep (value 2) is not available.


# instance fields
.field private final mCr:Landroid/content/ContentResolver;

.field private final mPm:Landroid/os/PowerManager;

.field private final mSensor:Landroid/hardware/Sensor;

.field private final mSm:Landroid/hardware/SensorManager;


# direct methods
.method constructor <init>(Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;Landroid/content/ContentResolver;)V
    .registers 5

    invoke-direct {p0}, Landroid/hardware/TriggerEventListener;-><init>()V

    iput-object p1, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mSm:Landroid/hardware/SensorManager;

    iput-object p2, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mSensor:Landroid/hardware/Sensor;

    iput-object p3, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mPm:Landroid/os/PowerManager;

    iput-object p4, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mCr:Landroid/content/ContentResolver;

    return-void
.end method


# virtual methods
.method public onTrigger(Landroid/hardware/TriggerEvent;)V
    .registers 8

    :try_start_0
    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mSm:Landroid/hardware/SensorManager;

    iget-object v1, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mSensor:Landroid/hardware/Sensor;

    invoke-virtual {v0, p0, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mCr:Landroid/content/ContentResolver;

    const-string v1, "pick_up_gesture_wakeup_mode"

    const/4 v2, 0x0

    const/4 v3, -0x2

    invoke-static {v0, v1, v2, v3}, Landroid/provider/Settings$System;->getIntForUser(Landroid/content/ContentResolver;Ljava/lang/String;II)I

    move-result v0

    const/4 v1, 0x1

    if-ne v0, v1, :goto_ret

    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;->mPm:Landroid/os/PowerManager;

    invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z

    move-result v1

    if-nez v1, :goto_ret

    const-string v1, "PortAodLongPress"

    const-string v2, "pickup: wake up"

    invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J

    move-result-wide v1

    const/16 v3, 0x10

    const-string v4, "com.android.systemui:PICK_UP"

    invoke-virtual {v0, v1, v2, v3, v4}, Landroid/os/PowerManager;->wakeUp(JILjava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :goto_ret
    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortAodLongPress"

    const-string v2, "pickup failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method
