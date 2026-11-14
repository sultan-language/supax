<div align="center">
<img src="https://raw.githubusercontent.com/sultan-language/sultanc-vscode/main/icons/sultanc-logo.svg" alt="SultanC" width="100">

**العربية** | [English](docs/en/README.md)

# سوباكس

**مدير حزم لغة السلطان، مكتوب بالسلطان.**

<p>
<img src="https://img.shields.io/badge/written%20in-SultanC-1a7f37?style=for-the-badge&labelColor=0d1117" alt="Written in SultanC">
<img src="https://img.shields.io/badge/messages-Arabic%20%2B%20English-8957e5?style=for-the-badge&labelColor=0d1117" alt="Messages">
<img src="https://img.shields.io/badge/macOS%20%7C%20Linux-yes-1a7f37?style=for-the-badge&labelColor=0d1117" alt="Platforms">
<img src="https://img.shields.io/badge/license-MIT-8b949e?style=for-the-badge&labelColor=0d1117" alt="License">
</p>

[التثبيت](#التثبيت) &nbsp;·&nbsp; [البداية](#البداية) &nbsp;·&nbsp; [ما يقدمه](#ما-يقدمه) &nbsp;·&nbsp; [الدليل](docs/ar/guide.md) &nbsp;·&nbsp; [فهرس الحزم](https://github.com/sultan-language/index)

</div>

<br>

<div dir="rtl">

سوباكس هو ما تكتبه بعد `sultanc`: ينشئ المشروع، ويجلب اعتمادياته من فهرس الحزم أو من git، ويثبّتها في `Supax.lock` حتى يُبنى المشروع غدا كما بُني اليوم، ثم يبني ويشغّل ويختبر. وهو نفسه برنامج بلغة السلطان، يبني نفسه بنفسه، وكل رسائله بالعربية أولا.

</div>

<br>

<table>
<tr><th width="55%"><code>Supax.toml</code></th><th width="45%"><code>src/main.sn</code></th></tr>
<tr>
<td valign="top">

```toml
[package]
name = "متجري"
version = "0.1.0"

[dependencies]
nahr  = "0.1"
json  = { git = "https://github.com/x/json" }
utils = { path = "../utils" }
```

</td>
<td valign="top" dir="rtl">

```
استورد المكتبة.دخ.println;

عرف الرئيسية(): عدد {
    اطبع_سطر("مرحبا من السلطان");
    أرجع 0;
}
```

</td>
</tr>
</table>

<div dir="rtl">

## التثبيت

بعد بناء المترجم ([sultanc](https://github.com/sultan-language/sultanc)) في مجلد مجاور:

</div>

```sh
git clone https://github.com/sultan-language/supax.git && cd supax
tools/install.sh ../sultanc
```

<div dir="rtl">

يضع السكربت `supax` و`sultanc` والمكتبة القياسية في `~/.supax`، ويضيفه إلى `PATH`، فيكفي فتح نافذة طرفية جديدة. وعلى ويندوز: `tools\install.ps1`.

## البداية

</div>

```console
$ supax new متجري && cd متجري
$ supax add nahr
        يجلب https://github.com/sultan-language/index
        أضاف nahr = "0.1.0"
$ supax run
        يبني متجري v0.1.0
       انتهى في 2.74 ث → build/bin/متجري
       يشغّل build/bin/متجري
```

<div dir="rtl">

## ما يقدمه

| الميزة | ما تعنيه |
|---|---|
| **فهرس حزم** | `nahr = "0.1"` يكفي. يُحل الإصدار من [الفهرس](https://github.com/sultan-language/index) بقواعد الإصدار الدلالي نفسها التي يتبعها Cargo |
| **بناء يتكرر** | `Supax.lock` يثبّت كل التزام وبصمته، ويعمل البناء دون شبكة بعد أول جلب (`--offline`) |
| **سلامة المحتوى** | كل حزمة لها بصمة SHA-256 تُفحص قبل كل استخدام، ولا يشغّل سوباكس أي شيفرة من حزمة مجلوبة |
| **مساحات عمل** | عدة حزم في مستودع واحد، بقفل واحد ومجلد `build/` واحد |
| **اختبارات** | `supax test` يشغّل دوال `@@اختبار` في المكتبة والبرامج ومجلد `tests/` |
| **أسماء عربية** | الحزم والبرامج والوحدات بأسماء عربية، مع حماية من الأسماء المتشابهة والمحارف الخفية |

## الأوامر الأساسية

| الأمر | ما يفعله |
|---|---|
| `supax new <الاسم>` | مشروع جديد |
| `supax add <الاسم>` | يضيف اعتمادية من الفهرس، أو `--git` أو `--path` |
| `supax build` / `run` / `test` | يبني، ويشغّل، ويختبر |
| `supax update` | يرفع الاعتماديات إلى أحدث إصدار متوافق |
| `supax tree` | شجرة الاعتماديات |
| `supax package` | يجهز إصدارا للنشر في الفهرس |

لكل أمر اسم عربي أيضا (`supax ابن`، `supax شغل`…). والقائمة كاملة مع الخيارات في [الدليل](docs/ar/guide.md).

## التوثيق

| الصفحة | ما فيها |
|---|---|
| [الدليل](docs/ar/guide.md) | كل الأوامر والخيارات، والبرامج، ومساحات العمل، والاختبارات، والمخبأ، والأمان |
| [صيغ الملفات](docs/ar/formats.md) | `Supax.toml` و`Supax.lock` وفهرس الحزم |
| [التكامل مع المترجم](docs/compiler-integration.md) | مخطط الحزم الذي يسلّمه سوباكس إلى `sultanc` |

## المساهمة

</div>

```sh
# البناء الأول
sultanc --package-graph=bootstrap/package-graph.toml src/main.sn -o build/bin/supax

# بعدها يبني سوباكس نفسه
build/bin/supax build

SULTANC=sultanc bash tests/run.sh
```

<div dir="rtl">

يحتاج سوباكس إلى `git`، وإلى مترجم السلطان `e1d4bca` أو أحدث (و`3b441bc` لأمر `supax test`).

<br>

<div align="center">

[الرخصة: MIT](LICENSE)

</div>

</div>
