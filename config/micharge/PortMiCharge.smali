.class public final Lmiui/util/PortMiCharge;
.super Ljava/lang/Object;
.source "PortMiCharge.smali"

# The Pixel 6a has no Xiaomi charger HAL (vendor.xiaomi.hardware.micharge); IMiCharge methods in miui-framework
# call this class instead (IMiCharge.methods.smali).
#
# Charge limit: Xiaomi writes protection modes through smart_chg (setMiChargePath) and night protection through
# setNightChargingState. Only properties are set here; init writes the charger nodes (port_charge.rc):
#   persist.sys.port.chg_common   always / high temperature / camera grip protection limit (0 = off)
#   persist.sys.port.chg_nav      navigation protection limit (0 = off)
#   persist.sys.port.chg_night    night (smart) protection limit (0 = off, 80 when on)
#   persist.sys.port.chg_start    resume level (limit - 5; 0 when unlimited)
#   persist.sys.port.chg_limit    effective limit = smallest of the above, 100 if none. init watches it
#   persist.sys.port.smart_chg    last smart_chg value written (read back by getMiChargePath)
# persist.sys.* is system_prop, settable by system_app and system_server.
#
# Battery health: read the Pixel battery nodes directly.

.method public constructor <init>()V
    .registers 1
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

# First line of a file, trimmed; null on failure
.method public static readLine(Ljava/lang/String;)Ljava/lang/String;
    .registers 4
    :try_start
    new-instance v1, Ljava/io/BufferedReader;
    new-instance v2, Ljava/io/FileReader;
    invoke-direct {v2, p0}, Ljava/io/FileReader;-><init>(Ljava/lang/String;)V
    invoke-direct {v1, v2}, Ljava/io/BufferedReader;-><init>(Ljava/io/Reader;)V
    invoke-virtual {v1}, Ljava/io/BufferedReader;->readLine()Ljava/lang/String;
    move-result-object v0
    invoke-virtual {v1}, Ljava/io/BufferedReader;->close()V
    :try_end
    .catch Ljava/lang/Exception; {:try_start .. :try_end} :catch
    if-eqz v0, :done
    invoke-virtual {v0}, Ljava/lang/String;->trim()Ljava/lang/String;
    move-result-object v0
    :done
    return-object v0
    :catch
    move-exception v1
    const/4 v0, 0x0
    return-object v0
.end method

.method private static setProp(Ljava/lang/String;Ljava/lang/String;)V
    .registers 4
    :try_start
    invoke-static {p0, p1}, Landroid/os/SystemProperties;->set(Ljava/lang/String;Ljava/lang/String;)V
    :try_end
    .catch Ljava/lang/Exception; {:try_start .. :try_end} :catch
    return-void
    :catch
    move-exception v0
    const-string v1, "PortMiCharge"
    invoke-static {v1, p0, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I
    return-void
.end method

# min(cur, property), ignoring values <= 0
.method private static minLevel(ILjava/lang/String;)I
    .registers 4
    const/4 v0, 0x0
    invoke-static {p1, v0}, Landroid/os/SystemProperties;->getInt(Ljava/lang/String;I)I
    move-result v0
    if-lez v0, :done
    if-ge v0, p0, :done
    move p0, v0
    :done
    return p0
.end method

# Compute the effective limit, write chg_start then chg_limit (init triggers on chg_limit and reads chg_start)
.method private static apply()V
    .registers 4
    const/16 v0, 0x64
    const-string v1, "persist.sys.port.chg_common"
    invoke-static {v0, v1}, Lmiui/util/PortMiCharge;->minLevel(ILjava/lang/String;)I
    move-result v0
    const-string v1, "persist.sys.port.chg_nav"
    invoke-static {v0, v1}, Lmiui/util/PortMiCharge;->minLevel(ILjava/lang/String;)I
    move-result v0
    const-string v1, "persist.sys.port.chg_night"
    invoke-static {v0, v1}, Lmiui/util/PortMiCharge;->minLevel(ILjava/lang/String;)I
    move-result v0
    # never below 50%
    const/16 v1, 0x32
    if-ge v0, v1, :ok
    move v0, v1
    :ok
    const/16 v1, 0x64
    if-lt v0, v1, :limited
    const/4 v1, 0x0
    goto :set
    :limited
    add-int/lit8 v1, v0, -0x5
    :set
    invoke-static {v1}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;
    move-result-object v1
    const-string v2, "persist.sys.port.chg_start"
    invoke-static {v2, v1}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    invoke-static {v0}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;
    move-result-object v1
    const-string v2, "persist.sys.port.chg_limit"
    invoke-static {v2, v1}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    return-void
.end method

# setMiChargePath("smart_chg", value), decimal or 0x hex:
#   low 16 bits = feature | enable (bit0), high 16 bits = limit. 0x10 = always protect (also high temperature and
#   camera grip), 0x2 = navigation. E.g. 0x500011 = always on at 80; 0x10 = always off; 0x500003 = navigation on.
#   Other features system_server writes (5, 8, 9, 0x101, 0x200, 0x201...) have no Pixel equivalent and are ignored.
.method public static setSmartChg(Ljava/lang/String;)Z
    .registers 6
    :try_start
    invoke-static {p0}, Ljava/lang/Integer;->decode(Ljava/lang/String;)Ljava/lang/Integer;
    move-result-object v0
    invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I
    move-result v0
    :try_end
    .catch Ljava/lang/Exception; {:try_start .. :try_end} :bad
    const-string v1, "persist.sys.port.smart_chg"
    invoke-static {v1, p0}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    const v1, 0xfffe
    and-int/2addr v1, v0
    and-int/lit8 v2, v0, 0x1
    ushr-int/lit8 v3, v0, 0x10
    if-nez v2, :enabled
    const/4 v3, 0x0
    :enabled
    invoke-static {v3}, Ljava/lang/String;->valueOf(I)Ljava/lang/String;
    move-result-object v3
    const/16 v4, 0x10
    if-ne v1, v4, :not_common
    const-string v4, "persist.sys.port.chg_common"
    invoke-static {v4, v3}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    goto :apply
    :not_common
    const/4 v4, 0x2
    if-ne v1, v4, :done
    const-string v4, "persist.sys.port.chg_nav"
    invoke-static {v4, v3}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    :apply
    invoke-static {}, Lmiui/util/PortMiCharge;->apply()V
    :done
    const/4 v0, 0x1
    return v0
    :bad
    move-exception v0
    const/4 v0, 0x0
    return v0
.end method

.method public static getSmartChg()Ljava/lang/String;
    .registers 2
    const-string v0, "persist.sys.port.smart_chg"
    const-string v1, "0"
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method

# Night (smart) protection: stop at 80% and finish before wake-up time (timing is up to Security); on/off only
.method public static setNight(I)Z
    .registers 3
    const-string v0, "0"
    if-eqz p0, :set
    const-string v0, "80"
    :set
    const-string v1, "persist.sys.port.chg_night"
    invoke-static {v1, v0}, Lmiui/util/PortMiCharge;->setProp(Ljava/lang/String;Ljava/lang/String;)V
    invoke-static {}, Lmiui/util/PortMiCharge;->apply()V
    const/4 v0, 0x1
    return v0
.end method

.method public static getNight()Ljava/lang/String;
    .registers 2
    const-string v0, "persist.sys.port.chg_night"
    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getInt(Ljava/lang/String;I)I
    move-result v0
    if-lez v0, :off
    const-string v0, "1"
    return-object v0
    :off
    const-string v0, "0"
    return-object v0
.end method

# Cycle count (Pixel google_battery)
.method public static getCycleCount()Ljava/lang/String;
    .registers 1
    const-string v0, "/sys/class/power_supply/battery/cycle_count"
    invoke-static {v0}, Lmiui/util/PortMiCharge;->readLine(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method

# Health in percent: capacity health index, or the overall health index if missing
.method public static getSoh()Ljava/lang/String;
    .registers 1
    const-string v0, "/sys/class/power_supply/battery/health_capacity_index"
    invoke-static {v0}, Lmiui/util/PortMiCharge;->readLine(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    if-nez v0, :done
    const-string v0, "/sys/class/power_supply/battery/health_index"
    invoke-static {v0}, Lmiui/util/PortMiCharge;->readLine(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    :done
    return-object v0
.end method
