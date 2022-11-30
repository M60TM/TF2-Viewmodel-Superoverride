# TF2-Viewmodel-Superoverride
A list of custom attributes make for v_model support

# Dependencies
- [TFCustAttr](https://github.com/nosoop/SM-TFCustAttr)
- [Econ Data](https://github.com/nosoop/SM-TFEconData)
- [TF2Utils](https://github.com/nosoop/SM-TFUtils) (0.11.0 or newer)

# Also Support
- [Custom Weapon X](https://github.com/nosoop/SM-TFCustomWeaponsX)

# How to Use

## Example:

- `"viewmodel superoverride"    "models/weapons/v_models/v_example.mdl"`

- `"armmodel superoverride"    "none"`

- `"viewmodel superoverride skin"   "2"`

- `"viewmodel superoffset"   "x=-5.0 y=-12.0 z=3.0 h=-4.0"`

- `"armmodel attachment"    "weapon_bone"`

- `"vm superoverride anim"	"fire=fire reload=reload"`

## Arguments:

- `"viewmodel superoverride"`: Attribute value is a full path to a model file, if you wanna worldmodel override, use [TFCWXBaseAttribute](https://github.com/nosoop/SM-TFCWXBaseAttributes).

- `"armmodel superoverride"`: Attribute value is a full path to a model file, default armmodels are already precached. If you don't set it, plugin find player's current class and automatically attach arm to weapon. And you can use `none` value to prevent arm attach(ex. quake rocketlauncher).

- `"viewmodel superoverride skin"`: Attribute value is a any number. Use it when you need to set specific skin.

- `"viewmodel superoffset"`: Attribute value is float vector. `x` is x axis angle(up-down), `y` is y axis angle(left-right), `z` is z axis angle(use it for spin). `h` is height of viewmodel.

- `"armmodel attachment"`: Attribute value is a attachment name. Even if "armmodel superoverride" is not set, it must be set unconditionally.

- `"vm superoverride anim"`: Available attribute value is `draw`, `idle`, `fire`(primary fire), `altfire`(alt fire), `reload`(reload or reload start), `reloadloop`, `reloadend`. You can also set playbackrate by using like `reloadPR=1.4`. Fire and altfire animation playbackrate follow original weapon playbackrate. So don't set `firePR=1.2`..