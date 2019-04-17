[TOC]

---

# 调研控件

## [flutter_html](https://pub.flutter-io.cn/packages/flutter_html)

- 基准版本：flutter_html 0.8.2

- 可取之处
    - 使用 Flutter Wrap 控件包装
    - 处理了首个换行标签的问题
    - 支持了标签自定义渲染方式

- 存在问题
    - 只对影响内容的关键标签的属性进行了处理，其他所有 style 均未处理；已处理 attributes 的 tag 和 attributes 如下：
        - a: href
        - bdo: dir
        - img: src, alt
        - td: colspan
        - th: colspan
    - 标签自定义渲染方式无法传递参数，如 img 的 src 参数
    - 只有叶子节点才可以使用单独定义的子控件，如：img，而可嵌套控件则无法使用

---

# 关键问题

- 将其中部分标签使用项目中的控件，如：图片用 cached_network_image
- 【重点】style 样式处理（优先级由高到低）
    - 内联样式
    - 内部样式
    - 外部样式
    - 默认样式
- 【重点】嵌套标签的处理
- 手势处理
    - 长按文字后的手势处理
    - 点击图片后的手势处理
    - 点击视频后的手势处理
- 特定标签操作表现
    - 标签 a 点击
        - UI 变色
        - 逻辑
            - 使用 web_view 跳转
            - 打开浏览器应用
    - 标签 img 点击
        - 逻辑处理
            - 全屏浏览图片
            - 长按保存
    - 标签 video 点击
        - 逻辑处理
            - 暂停/继续播放视频
            - 全屏播放
            - 音量调节
- 属性变换
    - 设备像素（px）转换逻辑像素（pt）
    - HTML 标签内部 em 与 px 转换
- 层级样式叠加处理
    - 样式类似作用域的处理方式

---

# 解决方案

## 自定义渲染逻辑

> 以 Img Tag 控件开发为例，用户可能使用 CachedNetworkImage 作为自定义渲染逻辑的主体控件，也可能使用 Image 控件作为自定义渲染逻辑的主体控件

- 效果需求：
    - 用户传入自定义控件的生成回调函数
    - HTML Parser 提供 HTML img 标签中相关的属性，如：src
- 关键问题：
    - 如何将用户传入的生成回调函数的参数与 HTML img 标签的属性一一对应？
        - 生成回调函数的由 Img Tag 控件去声明，由此限定了控件参数表由 Img Tag 来决定，也即使用 HTML img 标签的属性作为参数表
    - HTML img 标签数据是字符串，经过解析后字符串中的 attributes 属性转换为 Map，Map 又该如何与 Img Tag 构造函数的参数表一一对应？
        - 在 html_parser 的逻辑中去写这个一一对应的关系
    - HTML img 标签的 alt 属性可以响应 HTML style，HTML 文本的 style 在 Flutter 中的转换逻辑是什么？
        - 以 Flutter TextStyle 所支持的属性为依据提供对应的 HTML 文本的 style 属性的转换
    - HTML 文本 style 书写格式随意导致解析难度增加的处理方式：可以通过 font 属性直接定义所有 font 相关的样式，即 [CSS font 属性](http://www.runoob.com/cssref/pr-font-font.html)

## 样式优先级处理

> 只处理内联样式，内部样式因为无法解析 style 标签故无法处理；外部样式由于需要指定的 css 文件，故不处理；默认样式即 Flutter 的默认样式

- 优先级由高至低：内联样式 - 内部样式 - 默认样式
    - 内联样式：指的是 HTML 标签内指定的 style 属性

## 层级样式处理

> 顶层标签包含样式，底层标签包含内容的组合方式处理；即标签只作为样式的载体

示例：
```HTML
<!-- NOTE: 文本居中 -->
<p style="text-align: center;">
    <!-- NOTE: 文本字体大小，文本颜色 -->
    <span style="font-size: 24px; color: #003366;">
        <!-- NOTE: 文本内容 -->
        亲爱的游戏玩家：
    </span>
</p>
```

在递归解析标签时传递已解析样式的 Map 结构。
每次生成新的样式，继承自已解析样式，然后将当前层级中的样式添加/覆盖至继承的样式中。

```dart
Widget _parseNode(dom.Node node, {Map<String, String> styleMap}) {
    Map<String, String> effectiveStyle = new Map<String, String>();
    // NOTE: 继承父级
    if (styleMap != null && styleMap.isNotEmpty) {
      styleMap.forEach((String key, String value) => effectiveStyle[key] = styleMap[key]);
    }
    // NOTE: 合并并覆盖父级
    if (node.attributes.containsKey('style')) {
      Map<String, String> inlineStyle = parseInlineStyle(node.attributes['style']);
      inlineStyle.forEach((String key, String value) => effectiveStyle[key] = inlineStyle[key]);
    }
    // NOTE: ...
}

List<Widget> _parseNodeList(List<dom.Node> nodeList, {Map<String, String> styleMap}) {
    return nodeList.map((node) => _parseNode(node, styleMap: styleMap)).toList();
}
```

## 文本内联样式覆盖处理

> 对于文本的相关样式，可以在 style 中定义每一个样式，也可以在 font 属性中一次性定义多个。若在某标签的 style 属性中定义了文本相关的某种样式，如 font-size，又在 font 属性中定义了 font-size，此时会按照最后定义的样式作为最终渲染结果

在转换文本样式函数（convertTextStyle）中需要对其 font 属性进行解析并与 style 中已有属性进行叠加，关键处理步骤如下：

```dart
TextStyle convertTextStyle(Map<String, String> styleMap) {
    Map<String, String> effectiveStyleMap = new Map<String, String>();

    // NOTE: Map 是无序集合，使用 forEach 方法依次迭代每一个属性以保证 font 中的属性与其他 font 中同名的属性可以被依次替换
    // NOTE: 例：<p style="font:italic bold 16px/30px Georgia,serif; font-size: 12px;">，font-size 会替换 font 中的 font-size
    // NOTE: 例：<p style="font-style: italic; font:normal bold 16px/25px Georgia,serif; font-size: 12px;">
    // NOTE: font 中的 font-style 会替换 font-style，font-size 会替换 font 中的 font-size
    styleMap.forEach((String key, String value) {
        // NOTE: 使用 font 中的样式替换
        if (key == 'font') {
            // NOTE: font-style
            // NOTE: font-variant 暂不支持
            // NOTE: font-weight
            // NOTE: font-size/line-height
            // NOTE: font-family
        } else {
            effectiveStyleMap[key] = value;
        }
    });

    return (effectiveStyleMap == null || effectiveStyleMap.isEmpty) ? new TextStyle() : new TextStyle(
        // NOTE: 省略
    )
}
```

## 多层嵌套转换 Flutter 控件的衔接

> 标签嵌套按照这个第三方库的思路，将对应的标签转换到 Flutter 里面的 Wrap 控件。因为是直接按照递归的方式组成了这个 HTML 转 Flutter 组件的 UI 树，所以会有些组件之间衔接的问题。

**文本对齐问题** HTML 示例：

```html
<p font-size="24px">
    2018
    <span font-size="24px">
    9月
    </span>
    9日
</p>
```

p 标签的第一个节点是文本，只含有数字（同理字母）；第二个节点是 span 标签，span 标签内文本含有数字和中文；第三个节点也是数字和中文。

此 HTML 转换的 Flutter UI 树大致结构如下：

```dart
Wrap(
    children: [
        Text(
            '2018'
        ),
        Wrap(
            children: [
                '9月',
            ],
        ),
        Text(
            '9日',
        ),
    ],
);
```

可以看到，2018，9月，9日，分属不同的 Text 组件，此时在 Flutter 可视化调试中发现 数字/英文 的行高与含有中文的 Text 组件的行高不一致，导致了视觉上的文本不对齐效果。

初步判断，是 Flutter 自身框架的问题。

**截断换行问题** HTML 示例：

```html
<p>
    <span style="background-color: #ccffff;">
        温柔哼唱这首歌的BPM速度达到了123，属于音符速度比较快的歌曲，加上类型转换较快的音符，应对起来十分的困难
    </span>
    。这首歌的S评价需要718152分，首次挑战技能选择极限增强，在MISS掉8个音符的情况下最终得分为765150分，其中挑战得分较低最重要的原因，就是没有保持大量的S.PERFECT音符。
</p>
```

p 标签的文本内容和 span 标签的文本内容占据的行数都超过1行之后会导致显示结果按照标签的文本内容进行截断。

以上 HTML 转换 Flutter 控件之后的显示结果示例：
```text
温柔哼唱这首歌的BPM速度达到了123，属于音符速度比较快的歌曲，加上类型转换较快的音符，应对起来十分的困难
。这首歌的S评价需要718152分，首次挑战技能选择极限增强，在MISS掉8个音符的情况下最终得分为765150分，其中挑战得分较低最重要的原因，就是没有保持大量的S.PERFECT音符。
```

- 内嵌元素是否不应该转换为 Flutter 控件而是提供控件的额外修饰？
    - 至少 `span` 标签，`strong` 标签，`a` 标签看起来是这样子的

---

# 生成文档

## ImgTag 控件

- img 标签属性：[HTML img 标签 - runoob](http://www.runoob.com/tags/tag-img.html)
- 生成回调函数：
```dart
enum ImgCrossorigin {
  anonymous,
  use_credentials,
}

const Map<ImgCrossorigin, String> ImgCrossoriginMap = {
  ImgCrossorigin.anonymous: 'anonymous',
  ImgCrossorigin.use_credentials: 'use_credentials',
};

// NOTE: http://www.runoob.com/tags/tag-img.html
typedef ImgTagBuilder(
  BuildContext context, 
  String alt,
  String crossorigin,
  double height,
  double heightFactor,
  String src,
  double width,
  double widthFactor,
  TextStyle effectiveStyle,
);
```

## PTag 控件 - 暂时弃用

- p 标签属性：[HTML p 标签 - runoob](http://www.runoob.com/tags/tag-p.html)
- p 标签不能包含块级元素，同理：h1~h6，dt

## ATag 控件 - 暂时弃用

- a 标签属性：[HTML a 标签 - runoob](http://www.runoob.com/tags/tag-a.html)
- 点击回调函数：
```dart
typedef OnLinkTap(String url);
```

---

## HTML 文本 style 转换 Flutter TextStyle

- 影响 HTML 文本 style
    - font：font-style font-variant font-weight font-size/line-height font-family
    - color
    - direction
    - letter-spacing
    - line-height
    - text-align
    - text-decoration
    - text-indent
    - text-shadow
    - text-transform
    - unicode-bidi
    - vertical-align
    - white-space
    - word-spacing
    - font-family
    - font-size
    - font-style
    - font-variant
    - font-weight

- 转换影响表格

|HTML 文本 style|数据形式|Flutter 相关控件/属性|数据形式|备注|
|:-:|:-:|:-:|:-:|:-:|
|color/background-color|16进制|TextStyle.color/TextStyle.background|Color|-|
|color/background-color|RGB 值|TextStyle.color|Color.fromRGBO|-|
|color/background-color|RGBA 值|TextStyle.color|Color.fromRGBO with opacity = 1.0|-|
|color/background-color|HSL 值|TextStyle.color|暂不支持|-|
|color/background-color|HSLA 值|TextStyle.color|暂不支持|-|
|direction|ltr/rtl|Text.textDirection|TextDirection.ltr/TextDirection.rtl|-|
|letter-spacing|px 值|TextStyle.letterSpacing|pt 值|-|
|line-height|px 值|TextStyle.height|pt 值|-|
|text-align|center/left/right|Text.textAlign|TextAlign.center/TextAlign.left/TextAlign.right|Container.alignment|
|text-decoration|overline/line-through/underline|TextStyle.decoration|TextDecoration.overline/TextDecoration.lineThrough/TextDecoration.underline|-|
|text-indent|px 值|不支持|-|-|
|text-shadow|h-shadow/v-shadow/blur/color|TextStyle.shadows|暂不支持|-|
|text-transform|capitalize/uppercase/lowercase/inherit|String.toUppercase/String.toLowercase|-|-|
|unicode-bidi|normal/embed/bidi-override/initial/inherit|-|暂不支持|-|
|vertical-align|baseline/sub/super/top/text-top/middle/bottom/text-bottom/length/%/inherit|不支持|-|-|
|white-space|normal/pre/nowrap/pre-wrap/pre-line/inherit|不支持|-|-|
|word-spacing|px 值|TextStyle.wordSpacing|pt 值|-|
|font-family|字符串|TextStyle.fontFamily|字符串|-|
|font-size|px 值/%|TextStyle.fontSize|pt 值|-|
|font-style|italic/oblique|TextStyle.fontStyle|FontStyle.italic/不支持|-|
|font-variant|normal/small-caps/inherit|不支持|-|-|
|font-weight|normal/[double]|TextStyle.fontWeight|FontWeight.normal/FontWeight.w[double]|-|


---

# 开发日志

- 2019.1.28
    - 创建 Flutter HTML 转换开发文档
    - 通读 [flutter_html](https://pub.flutter-io.cn/packages/flutter_html) 源代码
    - 分析关键问题
- 2019.1.29
    - Flutter HTML 问题补充
    - 重构 Flutter HTML
    - Img Tag 尝试开发
- 2019.1.30
    - HTML 标签 style 属性与 Flutter 布局的转换
    - 发现 HTML style 的书写很随意，导致完整解析的难度骤增
    - HTML img 的 width 和 height 不仅可以直接指定数字（单位 px），也可以指定百分比（格式 n%）
- 2019.2.11
    - 影响 HTML 文本 style 总结
    - 在 *SizeAttribute* 中添加 em 到 px 的转换逻辑
    - String 到 Color 的转换函数：`Color string2Color(String colorString)`
    - 内联样式解析函数：`Map<String, String> parseInlineStyle(String styleString)`
- 2019.2.12
    - P Tag 尝试开发
    - 重新整理转换影响表格，罗列出支持和不支持的属性
    - 在 *SizeAttribute* 中添加字体相关的数值属性的获取方法
    - 文本样式转换函数：`TextStyle convertTextStyle(Map<String, String> styleMap)`
    - 解决文本样式的层级嵌套问题
    - A Tag 尝试开发
- 2019.2.13
    - 暂时弃用 P Tag 和 A Tag
    - 处理 p 标签的 text-align 属性
    - 处理原始 HTML 字符串中的特殊字符
    - 处理 HTML 文本 style 的 font 修饰与同层级其他文本修饰的叠加问题
- 2019.2.14
    - 遇到数字，字母，中文字符在不同 Text 控件中无法对齐的问题
    - 重新思考了一种方法，整个 HTML 采用富文本处理，用于解决文本无法对齐和截断换行的问题
    - 暂时弃用新的方法
    - 整合已实现内容到 flutter_html 0.8.2 版本的源码中
- 2019.2.15
    - 整合已实现内容到 flutter_html 0.8.2 版本的源码中
    - 通读 flutter_html 0.9.4 版本的源代码
    - 暂不使用 flutter_html 0.9.4 版本的源代码
    - 重构并启用 A Tag
    - 重构并启用 P Tag
    - Body Tag，B Tag，Span Tag，Strong Tag 开发
- 2019.2.16
    - 使用新方法：基于富文本 RealRichText 实现部分 HTML 标签的解析
    - 基于富文本 RealRichText 实现，需要图片尺寸信息，但是 HTML 标签不一定带有尺寸。如何获取图片的尺寸信息？
    - 采用插值分组的方法拆分 HTML 原始字符串
    - 基于先序遍历的 N 叉树关键路径的分组算法
- 2019.2.18
    - 基于先序遍历的 N 叉树关键路径的分组算法（引用传递方式）
- 2019.2.19
    - 基于广度优先遍历的 N 叉树关键路径剪枝算法（引用传递方式）
    - 基于剪枝树的 HTML DOM 树解析
    - 遇到 RealRichText 深层嵌套图片无法显示的问题，原因：RealRichText 在渲染图片时只处理了第一层（RealRichText children 中的 ImageSpan）的图片数据，尝试修改成递归渲染所有失败
- 2019.2.20
    - 不采用深层嵌套 TextSpan 的方式组织 RealRichText，只将各层的 style 向下传递，使用全局列表保存每一个需要生成文本的地方（解决 RealRichText 深层嵌套无效的问题）
    - 处理 RealRichText 中大图布局导致换行时连带上一个 TextSpan 的最后个别字符也换行的问题
- 2019.2.21
    - 处理块级标签嵌套时文本对齐方式的叠加问题
    - 细致化 N 叉树关键路径剪枝算法（处理路径重叠等问题）
- 2019.2.22
    - 文本添加背景色会导致部分文本颜色与背景色一致而“消失”
    - 处理文本行内图片的底部对齐问题

---

# 说明

## 实现思路

- 基于广度优先遍历的 N 叉树剪枝算法
- HTML DOM 树以块级元素为单位分组
- 每组标签转换为一段富文本处理

## 支持标签

- 内联标签
  - em
  - img
  - span
  - strong
  - source

- 块级标签
  - h1
  - h2
  - h3
  - h4
  - h5
  - h6
  - p
  - div
  - video

## 支持属性

- 文本相关属性

|HTML 文本 style|备注|
|:-:|:-:|
|color|HSL 值/HSLA 值 暂不支持|
|font-size||
|font-weight||
|font-style|仅支持 italic|
|letter-spacing||
|word-spacing||
|background-color||
|text-decoration||
|font-family|依文字样式资源而定|
|text-align|left/center/right|

## 关于不支持的标签/属性

对于不支持的标签/属性，会**直接读取标签中的文本内容，按照其对应的节点层级结构添加样式**，即：当作无样式内敛标签处理

## 遗留问题

- 文本设置背景颜色会导致部分文本内容与背景色相同而“消失”（Flutter 官方控件 Text.rich 也存在该问题）
    - 较新 Flutter 版本中该问题已修复

