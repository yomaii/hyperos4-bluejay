# Method replacements for miui/util/IMiCharge in miui-framework.jar (tools/jar_smali.py).
# The originals call Xiaomi's charger HAL. Method headers must match exactly (including the blacklist flag).

# smart_chg: charge protection switch and limit. Other nodes (fan, wireless charging) still return null.
.method public blacklist getMiChargePath(Ljava/lang/String;)Ljava/lang/String;
    .registers 3
    const-string v0, "smart_chg"
    invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :none
    invoke-static {}, Lmiui/util/PortMiCharge;->getSmartChg()Ljava/lang/String;
    move-result-object v0
    return-object v0
    :none
    const/4 v0, 0x0
    return-object v0
.end method

.method public blacklist setMiChargePath(Ljava/lang/String;Ljava/lang/String;)Z
    .registers 4
    const-string v0, "smart_chg"
    invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :none
    invoke-static {p2}, Lmiui/util/PortMiCharge;->setSmartChg(Ljava/lang/String;)Z
    move-result v0
    return v0
    :none
    const/4 v0, 0x0
    return v0
.end method

.method public blacklist getNightChargingState()Ljava/lang/String;
    .registers 2
    invoke-static {}, Lmiui/util/PortMiCharge;->getNight()Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method

.method public blacklist setNightChargingState(I)Z
    .registers 3
    invoke-static {p1}, Lmiui/util/PortMiCharge;->setNight(I)Z
    move-result v0
    return v0
.end method

# Required for the battery health page in Security
.method public blacklist isBatteryLifeFunctionSupported()Z
    .registers 2
    const/4 v0, 0x1
    return v0
.end method

.method public blacklist getBatteryCycleCount()Ljava/lang/String;
    .registers 2
    invoke-static {}, Lmiui/util/PortMiCharge;->getCycleCount()Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method

.method public blacklist getBatterySoh()Ljava/lang/String;
    .registers 2
    invoke-static {}, Lmiui/util/PortMiCharge;->getSoh()Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method
