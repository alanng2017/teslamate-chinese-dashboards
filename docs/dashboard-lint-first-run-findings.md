# Dashboard lint j–u 首跑发现清单

基线：v1.8.2；范围：`grafana/dashboards/{zh-cn,internal}/*.json` 共 48 份。

- 需产品判断：规则 k 共 438 个孤儿 `byName` matcher，聚合为 154 个面板；未自动修改。
- 规则 j/l/m/q/r：首跑无命中。
- 规则 n 已降为报告档，并保留 timeseries 的 `format: table`；被 `configRefId` 引用的配置帧会显式豁免。
- 规则 s 共将 5 个 dashboard 的 14 个 `rawSql` 字段、35 个 `[[...]]` token 改为 `${...}`；总数包含主会话补入的 `ChargingCostsStats.json` 3 个字段。

| 文件 | 面板 | 内容 | 建议 |
|---|---|---|---|
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 10 '总充电量 (kWh)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 33 '总免费充电量 (kWh)' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 64 '每公里电耗 (kWh/km)' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 38 '充电次数' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 66 '在$geofence的充电里程' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 65 '免费充电里程（无费用）' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `distance`, `car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 67 '超充站充电量' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 36 '总行驶里程' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `distance` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 56 '交流充电费用' | k：孤儿 byName matcher：`cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 44 '直流充电费用' | k：孤儿 byName matcher：`cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 14 '超充站充电费用' | k：孤儿 byName matcher：`cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 27 '总充电费用' | k：孤儿 byName matcher：`cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 40 '每100$length_unit费用' | k：孤儿 byName matcher：`distance`, `car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 42 '平均每度电费用' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 69 '行驶能耗' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `distance`, `car_id`, `efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 71 '综合能耗' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `range_loss`, `distance`, `car_id`, `efficiency`, `odometer` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 46 '充电站排名（按充电量）' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 4 '充电站排名（按费用）' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 34 '超级充电站排名' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 32 '免费充电站排名' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ChargingCostsStats.json` | panel 58 '每月统计' | k：孤儿 byName matcher：`Time driven`, `周期`, `效率`, `Energy charged`, `Avg charged`, `Costs`, `# charges`, `# drives`, `duration_min`, `usable_battery_level`, `cost`, `outside_temp`, `distance`, `consumption_kwh`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/ContinuousTrips.json` | panel 2 '长途行程' | k：孤儿 byName matcher：`outside_temp_f`, `consumption_kwh_mi`, `consumption_kwh_km`, `consumption_kwh`, `efficiency`, `usable_battery_level`, `outside_temp`, `distance`, `car_id`, `drive_id`, `power`, `battery_level`, `能耗` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 35 | k：孤儿 byName matcher：`添加能量`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 16 '里程表' | k：孤儿 byName matcher：`odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 5 | k：孤儿 byName matcher：`initial_range`, `rated_range`, `estimated_range` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 49 '电流' | k：孤儿 byName matcher：`Current`, `usable_battery_level`, `charger_voltage`, `charger_power`, `power`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 47 '电压' | k：孤儿 byName matcher：`usable_battery_level`, `charger_voltage`, `charger_power`, `power`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 34 '功率' | k：孤儿 byName matcher：`charger_voltage`, `charger_power`, `power` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentChargeView.json` | panel 24 | k：孤儿 byName matcher：`outside_temp`, `inside_temp`, `ac_temp`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentDriveView.json` | panel 24 '当前能耗' | k：孤儿 byName matcher：`range_loss`, `distance`, `car_id`, `efficiency`, `odometer` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentDriveView.json` | panel 32 '车辆标准能耗' | k：孤儿 byName matcher：`efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentDriveView.json` | panel 27 '距离' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentDriveView.json` | panel 14 '表显里程' | k：孤儿 byName matcher：`range_km`, `range_mi`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentDriveView.json` | panel 6 '里程表' | k：孤儿 byName matcher：`odometer_km`, `odometer_mi`, `odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 6 '当前状态' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 2 '最近状态改变(在线/离线/休眠)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 69 '续航/表显里程' | k：孤儿 byName matcher：`range_km`, `range_mi`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 70 '预估续航' | k：孤儿 byName matcher：`range_km`, `range_mi`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 71 '胎压 ($pressure_unit)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 79 '位置' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 55 '里程表' | k：孤儿 byName matcher：`odometer_km`, `odometer_mi`, `odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/CurrentState.json` | panel 57 '固件' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 44 | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 35 '平均充电量 (kWh)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 36 '平均耗电量 (kWh)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 34 '平均时间' | k：孤儿 byName matcher：`duration_min`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 37 '平均费用' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/DCChargingCurvesByCarrier.json` | panel 38 '平均每度电费用' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/IncompleteData.json` | panel 2 '车辆信息 🚘' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/IncompleteData.json` | panel 15 '不完整的行程 🛣️' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/IncompleteData.json` | panel 22 '不完整的充电 🪫' | k：孤儿 byName matcher：`car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/MileageStats.json` | panel 10 '每${period}统计' | k：孤儿 byName matcher：`行驶时长`, `周期`, `效率`, `行程次数`, `duration_min`, `usable_battery_level`, `distance`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedRates.json` | panel 2 '不同速度下的能耗 - $terrain_type 地形' | k：孤儿 byName matcher：`distance`, `car_id`, `odometer`, `drive_id`, `power` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedRates.json` | panel 6 '已记录里程' | k：孤儿 byName matcher：`distance_km`, `distance_mi`, `distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedRates.json` | panel 4 '行驶能耗' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `distance`, `car_id`, `efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedRates.json` | panel 8 '综合能耗' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `range_loss`, `distance`, `car_id`, `efficiency`, `odometer` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedRates.json` | panel 14 '当前标准能效' | k：孤儿 byName matcher：`efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedTemperature.json` | panel 26 '按速度与温度的能耗 (Wh/$length_unit)' | k：孤儿 byName matcher：`speed\temperature` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedTemperature.json` | panel 15 '按速度与温度的续航 ($length_unit)' | k：孤儿 byName matcher：`speed\temperature` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/SpeedTemperature.json` | panel 24 '按速度与温度的行驶距离占比' | k：孤儿 byName matcher：`speed\temperature` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/TrackingDrives.json` | panel 16 '耗电量' | k：孤儿 byName matcher：`efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/TrackingDrives.json` | panel 10 '海拔' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/battery-health.json` | panel 13 '电池容量 (kWh)' | k：孤儿 byName matcher：`可用容量(新车)`, `可用容量(现在)`, `差异` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/battery-health.json` | panel 37 '行程统计' | k：孤儿 byName matcher：`行驶里程`, `Data lost (not logged)`, `总里程`, `distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/battery-health.json` | panel 36 '电池统计' | k：孤儿 byName matcher：`# of Charges`, `# of Charging cycles`, `Charging Efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/battery-health.json` | panel 32 '能耗' | k：孤儿 byName matcher：`efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 10 | k：孤儿 byName matcher：`charge_energy_added`, `charge_energy_added`, `charge_energy_used` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 20 | k：孤儿 byName matcher：`charge_energy_used`, `charge_energy_added` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 14 | k：孤儿 byName matcher：`cost`, `charge_energy_added`, `charge_energy_used` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 15 | k：孤儿 byName matcher：`duration_min`, `charge_energy_added`, `charge_energy_used` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 6 '充电桩类型: $charge_type' | k：孤儿 byName matcher：`efficiency`, `outside_temp`, `distance`, `charger_voltage`, `odometer`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charges.json` | panel 17 '不完整的充电记录 🪫' | k：孤儿 byName matcher：`car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 8 '次数' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 10 '累计总电量' | k：孤儿 byName matcher：`sum`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 14 '超充总费用 (¥)' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 27 '累计充电总费用 (¥)' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 26 '每百 $length_unit 费用' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 31 '平均每度电价格' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 32 '平均每度电价格 DC' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 33 '平均每度电价格 AC' | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 2 '充电结束时电量' | k：孤儿 byName matcher：`duration_min`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 13 '充电开始时电量' | k：孤儿 byName matcher：`duration_min`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 4 '充电站排序 (按电量)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/charging-stats.json` | panel 6 '充电站排序 (按费用)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 32 '里程' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 36 '统计' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 39 '软件' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 42 '不完整的数据' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 38 | k：孤儿 byName matcher：`Row Count` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 41 '索引' | k：孤儿 byName matcher：`Index Size`, `Index`, `Tuples Fetched` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 45 '前20条语句 (按平均执行时间排序)' | k：孤儿 byName matcher：`Calls`, `Query`, `Mean Exec Time`, `Total Exec Time`, `calls`, `mean_exec_time`, `total_exec_time`, `query` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/database-info.json` | panel 46 '前20条语句 (按总执行时间排序)' | k：孤儿 byName matcher：`Calls`, `Query`, `Mean Exec Time`, `Total Exec Time`, `calls`, `mean_exec_time`, `total_exec_time`, `query` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 20 '行程次数' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 16 '总里程' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 22 '已用电量' | k：孤儿 byName matcher：`efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 26 '每次行驶里程中位数' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 8 '平均每天行驶距离' | k：孤儿 byName matcher：`distance_km`, `distance_mi` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 33 '最大速度' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 35 '最大速度 (最近30天)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 34 '最大速度 (最近七天)' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 32 '预估每月里程数' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drive-stats.json` | panel 30 '估计年行驶里程' | k：孤儿 byName matcher：`yearly_mileage_km`, `yearly_mileage_mi` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 4 | k：孤儿 byName matcher：`consumption_kWh` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 5 | k：孤儿 byName matcher：`duration_min` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 6 | k：孤儿 byName matcher：`distance_mi`, `distance_km` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 7 | k：孤儿 byName matcher：`consumption_kwh_mi`, `consumption_kwh_km` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 2 '行程' | k：孤儿 byName matcher：`id`, `usable_battery_level`, `outside_temp`, `distance`, `consumption_kwh`, `power`, `battery_level`, `end_date` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/drives.json` | panel 9 '不完整的行程 🛣️' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 4 '能耗（行驶）' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `distance`, `car_id`, `efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 8 '能耗 (总计)' | k：孤儿 byName matcher：`consumption_km`, `consumption_mi`, `range_loss`, `distance`, `car_id`, `efficiency`, `odometer` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 6 '记录的距离' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 2 '温度 – 能效' | k：孤儿 byName matcher：`duration_min`, `outside_temp`, `distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 14 '当前额定能效' | k：孤儿 byName matcher：`efficiency`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 12 '理想能效推算' | k：孤儿 byName matcher：`duration_min`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/efficiency.json` | panel 15 '额定能效推算' | k：孤儿 byName matcher：`duration_min`, `car_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/locations.json` | panel 12 '地址' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/locations.json` | panel 22 '足迹' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/locations.json` | panel 2 '地点' | k：孤儿 byName matcher：`updated_at`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/locations.json` | panel 6 '收藏点' | k：孤儿 byName matcher：`时间`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 14 '平均能耗(净值)' | k：孤儿 byName matcher：`distance`, `car_id`, `efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 22 '平均能耗（总计）' | k：孤儿 byName matcher：`range_loss`, `distance`, `car_id`, `efficiency`, `odometer` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 24 '总行驶里程' | k：孤儿 byName matcher：`distance`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 25 '剩余续航' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 2 '固件版本' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/overview.json` | panel 6 '里程表' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/states.json` | panel 2 '上次状态变更时间' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/states.json` | panel 6 '当前状态' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/states.json` | panel 8 '停车比 (%)' | k：孤儿 byName matcher：`duration_min`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/statistics.json` | panel 2 '每${period}' | k：孤儿 byName matcher：`驾驶时间`, `周期`, `驾驶效率`, `用电量`, `平均每次充电`, `费用`, `充电次数`, `行驶次数`, `平均电价`, `平均百公里费用`, `额外能耗开销`, `duration_min`, `usable_battery_level`, `cost`, `range_loss`, `odometer`, `outside_temp`, `distance`, `car_id`, `drive_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/timeline.json` | panel 2 '时间线' | k：孤儿 byName matcher：`duration_min`, `outside_temp`, `distance`, `car_id`, `efficiency`, `odometer`, `drive_id`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 10 | k：孤儿 byName matcher：`odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 26 | k：孤儿 byName matcher：`odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 28 | k：孤儿 byName matcher：`distance`, `odometer`, `car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 30 | k：孤儿 byName matcher：`distance`, `car_id`, `efficiency` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 32 | k：孤儿 byName matcher：`range_loss`, `distance`, `car_id`, `efficiency`, `odometer`, `drive_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 22 | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 2 '行程' | k：孤儿 byName matcher：`usable_battery_level`, `outside_temp`, `distance`, `consumption_kwh`, `efficiency`, `battery_level`, `end_date` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/trip.json` | panel 36 '充电' | k：孤儿 byName matcher：`outside_temp`, `distance`, `efficiency`, `odometer`, `battery_level`, `end_date` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/updates.json` | panel 8 '系统更新' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/updates.json` | panel 6 '两次更新平均间隔' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/updates.json` | panel 2 '更新' | k：孤儿 byName matcher：`car_id`, `usable_battery_level`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/vampire-drain.json` | panel 2 '停车电量消耗' | k：孤儿 byName matcher：`usable_battery_level`, `odometer`, `efficiency`, `car_id`, `power`, `battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/visited.json` | panel 5 | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/visited.json` | panel 6 | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/zh-cn/visited.json` | panel 7 | k：孤儿 byName matcher：`car_id`, `cost` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/charge-details.json` | panel 12 '电池电量' | k：孤儿 byName matcher：`battery_level` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/charge-details.json` | panel 13 '平均功率' | k：孤儿 byName matcher：`charger_voltage`, `charger_power`, `power` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/charge-details.json` | panel 15 '平均室外温度' | k：孤儿 byName matcher：`outside_temp` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 38 '里程表 (起 - 止)' | k：孤儿 byName matcher：`drive_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 14 '行驶时长' | k：孤儿 byName matcher：`drive_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 20 '海拔摘要' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 12 '能耗 (净)' | k：孤儿 byName matcher：`efficiency`, `car_id`, `drive_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 40 '能量回收' | k：孤儿 byName matcher：`drive_id`, `power` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
| `grafana/dashboards/internal/drive-details.json` | panel 37 '平均速度' | k：孤儿 byName matcher：`car_id` | 核对是否为历史残留；确认无运行时输出后删除 override，仍需显示规则则改为当前 SQL 输出名。 |
