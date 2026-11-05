# alsa-ucm-conf: handheld profiles

`ucm2/` here is laid over upstream's tree by the recipe (new files only). The profiles come from
[ROCKNIX](https://github.com/ROCKNIX/distribution) (`projects/ROCKNIX/packages/audio/alsa-ucm-conf`,
branch `next`: its `patches/SDM845`, `SM8250`, `SM8550`, `SM8650`, `SM8750` and `sources/ucm2`),
applied to alsa-ucm-conf 1.2.16.1. ROCKNIX is distributed under GPL-2.0.

| Device | SoC | Profile | Card (conf.d) | Authors |
|---|---|---|---|---|
| AYN Odin | SDM845 | `AYN/Odin` | `sdm845/AYN Odin` | Anton Bambura, Jacob Cook |
| AYN Odin 2 / Mini / Portal | SM8550 | `AYN/Odin2` | `sm8550/AYN-Odin2`, `ayn-AYNOdin2-` | Teguh Sobirin |
| AYN Thor | SM8550 | `AYN/Thor` | `sm8550/AYN-Thor`, `ayn-AYNThor-` | Luke Johnson |
| AYANEO Pocket ACE / DMG / DS / EVO | SM8550 | `AYANEO/Pocket` | `sm8550/SM8550-APS`, `ayaneo-AYANEOPocket*-` | ROCKNIX contributors |
| AYANEO Pocket S2 | SM8650 | `Qualcomm/sm8650/APS2` | `sm8650/SM8650-APS2`, `ayaneo-AYANEOPocketS2-` | ROCKNIX contributors |
| AYN Odin 3 | SM8750 | `AYN/Odin3` | `sm8750/SM8750-AYN`, `ayn-AYNOdin3-` | Teguh Sobirin |
| Retroid Pocket 5 / Mini / Mini V2 / Flip 2 | SM8250 | `Qualcomm/sm8250/RetroidPocket` (+ HDMI) | `sm8250/RetroidPocket`, `retroid*-RetroidPocket*` | Teguh Sobirin |
| AYN Thor Lite | SM8250 | `Qualcomm/sm8250/AYN-Thor-Lite` | `sm8250/AYN Thor Lite`, `ayn-ATNThorLite-` | ROCKNIX contributors |
| Mangmi AIR Y Pro, Pocket Max | SM8250 | `Qualcomm/sm8250/AirYPro`, `PocketMax` | `sm8250/AirYPro`, `PocketMax` | ROCKNIX contributors |
| Retroid Pocket Duo Lite | SM6125 | `Qualcomm/sm6125/RetroidPocketDuoLite` | `sm4250/RetroidPocketDuoLite` | ROCKNIX contributors |
| Mangmi AIR X, AIR Y | SM6115 | `Qualcomm/sm6115/MangmiAirX`, `MangmiAirY` | `sm4250/MangmiAirX`, `MangmiAirY` | ROCKNIX contributors |

`codecs/wsa881x/init.conf` (the WSA881x speaker amplifiers' stereo volume) is shared by the
Retroid profiles. The `conf.d` names with a trailing `-` are the long names the kernel makes from
the DMI tables (`vendor-product-`) when the device boots through UEFI; the others are the device
tree's model of the sound card. `retroid-RetroidPocket5-.conf` and the `retroidpocket-*-.conf`
links are CleanLinux's: ROCKNIX's `retroid-RetroidPocket5-conf` lacks the dot, and its patch
names both forms.
