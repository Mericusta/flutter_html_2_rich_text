import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:cached_network_image/cached_network_image.dart';

import 'styles/size_attribute.dart';
import 'styles/tag_rule.dart';
import 'utils/utils.dart';
import 'package:flutter_rich_text/CustomImageSpan.dart';
import 'package:flutter_rich_text/CustomRichText.dart';

const List<String> inlineTagList = [
  'em',
  'img',
  'span',
  'strong',
  'source',
];

const List<String> blockTagList = [
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'p',
  'div',
  'video',
];

// NOTE: 关键节点
const List<String> truncateTagList = [
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'p',
  'div',
  'video',
];

List<Widget> parse(String originHtmlString) {
  dom.Document document = parser.parse(originHtmlString);

  // NOTE: 先序遍历找到所有关键节点的个数
  int keyNodeCount = 0;
  preorderTraversalNTree(document.body, f: (dom.Node childNode) {
    if (childNode is dom.Element && truncateTagList.indexOf(childNode.localName) != -1) {
      // print('TEST: 第 ${keyNodeCount + 1} 个关键节点：');
      // checkNodeType(childNode);
      keyNodeCount++;
    }
  });

  // print('TEST: 共 $keyNodeCount 个关键节点');

  List<dom.Node> splitNodeList = new List<dom.Node>();

  // NOTE: 关键路径作为边界（无边界不剪枝）
  // DEBUG: 使用 continue 会崩溃，原因未知
  for (int index = -1; index < keyNodeCount; ++index) {
    // print('TEST: index = $index');
    
    // NOTE: szO 深拷贝 Osz
    dom.Node cloneNode = document.body.clone(true); 

    // NOTE: 先序遍历找到所有关键节点（由于是引用传值，所以需要重新获取一遍 hashCode）
    List<dom.Node> keyNodeList = new List<dom.Node>();
    preorderTraversalNTree(cloneNode, f: (dom.Node childNode) {
      if (childNode is dom.Element && truncateTagList.indexOf(childNode.localName) != -1) {
        keyNodeList.add(childNode);
      // // NOTE: 对于占据整行的图片也作为关键节点处理
      // } else if (childNode is dom.Element && checkImageNeedNewLine(childNode.attributes['width'], childNode.attributes['height'])) {

      }
    });

    // NOTE: 获得关键路径
    List<List<dom.Node>> _keyNodeRouteList = new List<List<dom.Node>>();
    for (var keyNode in keyNodeList) {
      var list = new List<dom.Node>();
      var node = keyNode;
      while (node != null && (node as dom.Element).localName != 'body') {
        list.add(node);
        node = node.parent;
      }
      _keyNodeRouteList.add(list);
    }

    List<dom.Node> keyNodeRouteLeft = index == -1 ? null : _keyNodeRouteList[index];
    List<dom.Node> keyNodeRouteRight = (index + 1) < _keyNodeRouteList.length ? _keyNodeRouteList[index + 1] : null;

    // NOTE: 延伸边界至含有关键节点的叶子节点（先序遍历）
    if (keyNodeRouteLeft != null) {
      dom.Node node = keyNodeRouteLeft.first;
      while (node.hasChildNodes()) {
        bool found = false;
        for (var keyNode in node.nodes) {
          if (keyNode is dom.Element && truncateTagList.contains(keyNode.localName)) {
            node = keyNode;
            found = true;
            keyNodeRouteLeft.insert(0, node);
            break;
          }
        }
        if (!found) {
          break;
        }
      }
    }
    if (keyNodeRouteRight != null) {
      dom.Node node = keyNodeRouteRight.first;
      while (node.hasChildNodes()) {
        bool found = false;
        for (var keyNode in node.nodes) {
          if (keyNode is dom.Element && truncateTagList.contains(keyNode.localName)) {
            node = keyNode;
            found = true;
            keyNodeRouteRight.insert(0, node);
            break;
          }
        }
        if (!found) {
          break;
        }
      }
    }

    // NOTE: 检查一条边界是否包含另一条边界
    // NOTE: 边界包含边界：指的是，某一边界的关键节点的子节点包含另一边界
    // NOTE: 在关键路径的列表中的体现就是不同长度的列表的交集为某一边界
    // NOTE: 如果左边界包含右，则延伸左边界至其先序遍历的叶子节点，这里不考虑右包含左（先序遍历）
    bool isContain = true;
    // NOTE: 检查边界重合
    // NOTE: 边界重合：指的是，两条边界的关键节点完全重合
    // NOTE: 在关键路径的列表中的体现就是列表完全相同
    // NOTE: 若边界重合，则不处理
    bool isCoincide = true;
    if (keyNodeRouteLeft != null && keyNodeRouteLeft.isNotEmpty && keyNodeRouteRight != null && keyNodeRouteRight.isNotEmpty) {
      if (keyNodeRouteLeft.length < keyNodeRouteRight.length) {
        isCoincide = false;
        for (var node in keyNodeRouteLeft) {
          if (!keyNodeRouteRight.contains(node)) {
            isContain = false;
            break;
          }
        }
        if (isContain) {
          dom.Node node = keyNodeRouteLeft.first;
          while (node.hasChildNodes()) {
            node = node.nodes.first;
            keyNodeRouteLeft.insert(0, node);
          }
        }
      } else if (keyNodeRouteLeft.length > keyNodeRouteRight.length) {
        isCoincide = false;
        for (var node in keyNodeRouteRight) {
          if (!keyNodeRouteLeft.contains(node)) {
            isContain = false;
            break;
          }
        }
        if (isContain) {
          dom.Node node = keyNodeRouteRight.first;
          while (node.hasChildNodes()) {
            node = node.nodes.first;
            keyNodeRouteRight.insert(0, node);
          }
        }
      } else {
        for (dom.Node leftNode in keyNodeRouteLeft) {
          if (!keyNodeRouteRight.contains(leftNode)) {
            isCoincide = false;
            break;
          }
        }
      }
    } else {
      isContain = false;
      isCoincide = false;
    }

    // // print('TEST: 左关键路径（左边界）：');
    // keyNodeRouteLeft?.forEach((keyNode) => checkNodeType(keyNode));
    
    // // print('TEST: 右关键路径（右边界）：');
    // keyNodeRouteRight?.forEach((keyNode) => checkNodeType(keyNode));
    
    if (!isCoincide) {
      // NOTE: 裁剪关键节点
      // print('TEST: 裁剪关键节点');
      removeNodeInBreadthFirstTraversalNTree(cloneNode, 0, keyNodeRouteLeft, keyNodeRouteRight);

      // NOTE: 保存节点
      // print('TEST: 保存节点：');
      // preorderTraversalNTree(cloneNode);
      // NOTE: 不保存空节点（剪枝结果只剩下根节点）
      if (!(cloneNode.hasChildNodes()) && cloneNode is dom.Element && cloneNode.localName == 'body') {
        // print('TEST: 剩余根节点，不保存节点');
      } else {
        splitNodeList.add(cloneNode);
      }
    } else {
      // print('TEST: 边界重合，不裁剪');
    }

    if (!isCoincide) {
      // NOTE: 保存边界
      // print('TEST: 如果边界内没有关键路径，则保存边界：');
      if (keyNodeRouteRight != null) {
        bool hasKeyRouteNode = false;
        preorderTraversalNTree(keyNodeRouteRight.first, f: (dom.Node childNode) {
          if (childNode.parent.localName != 'body' && childNode is dom.Element && truncateTagList.indexOf(childNode.localName) != -1) {
            // print('TEST: 含有关键节点');
            // checkNodeType(childNode);
            hasKeyRouteNode = true;
          }
        });
        if (!hasKeyRouteNode) {
          splitNodeList.add(keyNodeRouteRight.first);
        }
      }
    } else {
      // print('TEST: 不保存边界');
    }
  }

  // int splitNodeIndex = 0;
  // for (dom.Node splitNode in splitNodeList) {
  //   print('TEST: splitNodeIndex = ${splitNodeIndex++}');
  //   preorderTraversalNTree(splitNode);
  // }

  List<Widget> widgetList = parseNode2Flutter(splitNodeList);
  return widgetList;
}

// NOTE: 自上而下合并树并转换成 Flutter 控件

// NOTE: 富文本控件在父控件中的对齐方式
Alignment richTextAlignment;
// NOTE: 富文本控件的基线数值，默认字号大小
double baseLineValue;

List<Widget> parseNode2Flutter(List<dom.Node> nodeList) {
  List<Widget> widgetList = new List<Widget>();
  
  for (dom.Node node in nodeList) {
    // print('TEST: 转换节点：');
    // checkNodeType(node);
    richTextAlignment = Alignment.centerLeft;
    baseLineValue = 14.0;
    // NOTE: 向下合并
    if (node is dom.Element && node.localName == 'video') {
      String sourceUrl = '';
      for (dom.Node videoNode in node.nodes) {
        if (videoNode is dom.Element && videoNode.localName == 'source') {
          if (videoNode.attributes.containsKey('src') && videoNode.attributes['src'] != null) {
            sourceUrl = videoNode.attributes['src'];
            break;
          }
        }
      }
      widgetList.add(new Container(
        width: DeviceAttribute.screenWidth,
        child: new Center(
          // child: new NetworkVideoPlayer(
          //   sourceUrl,
          //   autoPlay: false,
          // ),
        ),
      ));
    } else {
      List<TextSpan> textSpanList = new List<TextSpan>();
      _parseNode2TextSpanTest(node, textSpanList);
      widgetList.add(new Container(
        alignment: richTextAlignment,
        child: new Baseline(
          baseline: baseLineValue, // NOTE: 当前富文本段中的最大高度,
          baselineType: TextBaseline.alphabetic,
          child: new CustomRichText(
            textSpanList,
          ),
        ),
      ));
    }
  }

  return widgetList;
}

void _parseNode2TextSpanTest(dom.Node node, List<TextSpan> textSpanList, {Map<String, String> styleMap}) {
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

  // NOTE: 获取对齐方式
  if (effectiveStyle.containsKey('text-align')) {
    richTextAlignment = AlignmentMap[effectiveStyle['text-align']];
  }
  
  // NOTE: 获取基线最大值
  if (effectiveStyle.containsKey('font-size')) {
    if (SizeAttribute(effectiveStyle['font-size']).fontStyleValue > baseLineValue) {
      baseLineValue = SizeAttribute(effectiveStyle['font-size']).fontStyleValue;
    }
  }

  // NOTE: 标签
  if (node is dom.Element) {
    switch (node.localName) {
      case 'a':
        effectiveStyle['text-decoration'] = 'underline';
        break;
      case 'b':
        effectiveStyle['font-weight'] = 'bold';
        break;
      case 'em':
        effectiveStyle['font-style'] = 'italic';
        break;
      case 'h1':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '28px';
        break;
      case 'h2':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '21px';
        break;
      case 'h3':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '16px';
        break;
      case 'h4':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '14px';
        break;
      case 'h5':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '12px';
        break;
      case 'h6':
        effectiveStyle['font-weight'] = 'bold';
        effectiveStyle['font-size'] = '10px';
        break;
      case 'img':
        Map<String, double> imageSize = getImageSize(new SizeAttribute(node.attributes['width'] ?? '100%').imgValue, new SizeAttribute(node.attributes['height'] ?? '100%').imgValue);
        bool newLine = imageSize['width'] >= DeviceAttribute.screenWidth;
        if (baseLineValue < imageSize['height'] && !newLine) {
          baseLineValue = imageSize['height'];
        }
        if (newLine) {
          textSpanList.add(new TextSpan(text: '\n'));
        }
        textSpanList.add(new CustomImageSpan(
          new CachedNetworkImageProvider(node.attributes['src']),
          imageWidth: imageSize['width'] - (newLine ? 30.0 : 0.0),
          imageHeight: imageSize['height'],
          fontSize: newLine ? null : baseLineValue,
        ));
        if (newLine) {
          textSpanList.add(new TextSpan(text: '\n'));
        }
        return;
      case 'p':
        break;
      case 'span':
        break;
      case 'strong':
        effectiveStyle['font-weight'] = 'bold';
        break;
      default:
        break;
    }

    _parseNodeListTest(node.nodes, textSpanList, styleMap: effectiveStyle);
  } else if (node is dom.Text) {
    if (node.text.trim() == '' && node.text.indexOf(' ') == -1) {
      return;
    }
    if (node.text.trim() == '' && node.text.indexOf(' ') != -1) {
      node.text = ' ';
    }

    String finalText = trimStringHtml(node.text);

    textSpanList.add(new TextSpan(
      text: finalText,
      style: convertTextStyle(effectiveStyle),
    ));
  }
}

void _parseNodeListTest(List<dom.Node> nodeList, List<TextSpan> textSpanList, {Map<String, String> styleMap, Alignment alignment}) {
  nodeList.forEach((dom.Node node) => _parseNode2TextSpanTest(node, textSpanList, styleMap: styleMap));
}

TextSpan _parseNode2TextSpan(dom.Node node, {Map<String, String> styleMap}) {
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

  // NOTE: 标签
  if (node is dom.Element) {
    // NOTE: 先检查是否支持该标签，避免 switc case 的消耗
    if (!supportedElements.contains(node.localName)) {
      return TextSpan();
    }

    switch (node.localName) {
      case 'a':
        effectiveStyle['text-decoration'] = 'underline';
        break;
      case 'b':
        effectiveStyle['font-weight'] = 'bold';
        break;
      case 'img':
        return new CustomImageSpan(
          new CachedNetworkImageProvider(node.attributes['src']),
          imageWidth: new SizeAttribute(node.attributes['width'] ?? '100%').imgValue,
          imageHeight: new SizeAttribute(node.attributes['height'] ?? '100%').imgValue,
        );
      case 'p':
        break;
      case 'span':
        break;
      case 'strong':
        effectiveStyle['font-weight'] = 'bold';
        break;
      default:
        break;
    }

    print(effectiveStyle);

    return new TextSpan(
      children: _parseNodeList(node.nodes, styleMap: effectiveStyle),
      style: convertTextStyle(effectiveStyle),
    );
    // return _parseNode2TextSpan(node, styleMap: effectiveStyle);
  } else if (node is dom.Text) {
    if (node.text.trim() == '' && node.text.indexOf(' ') == -1) {
      return new TextSpan();
    }
    if (node.text.trim() == '' && node.text.indexOf(' ') != -1) {
      node.text = ' ';
    }

    String finalText = trimStringHtml(node.text);

    return new TextSpan(
      text: finalText,
      style: convertTextStyle(effectiveStyle),
    );
  }

  return new TextSpan();
}

List<TextSpan> _parseNodeList(List<dom.Node> nodeList, {Map<String, String> styleMap}) {
  return nodeList.map((node) => _parseNode2TextSpan(node, styleMap: styleMap)).toList();
}

String trimStringHtml(String stringToTrim) {
  stringToTrim = stringToTrim.replaceAll('\n', '');
  while (stringToTrim.indexOf('  ') != -1) {
    stringToTrim = stringToTrim.replaceAll('  ', ' ');
  }
  return stringToTrim;
}

// NOTE: utility
typedef TraversalOperation(dom.Node node);
void checkNodeType(dom.Node node) {
  if (node is dom.Element) {
    print('TEST: element = ${node.localName}');
  } else if (node is dom.Text) {
    print('TEST: text = ${node.text}');
  } else {
    print('TEST: node = ${node.runtimeType}');
  }
}

// NOTE: 检查关键路径中的节点的所有子节点是否是子支的第一个/最后一个节点
bool checkKeyRouteNodes(dom.Node keyRouteNode, List<dom.Node> keyRouteNodeList, bool isFirst) {
  // print('TEST: checkKeyRouteNodes');
  // checkNodeType(keyRouteNode);
  // NOTE: 当被检查的节点是关键节点时，检查完毕
  // NOTE: 关键节点：因为关键路径可能是因为在路径重合时延伸出来的，所以关键节点还得是预设的截断点
  if (keyRouteNode == keyRouteNodeList.first && keyRouteNode is dom.Element && truncateTagList.contains(keyRouteNode.localName)) {
    return true;
  }
  // NOTE: 当被检查的节点不是第一个/最后一个节点
  if (keyRouteNode is dom.Text || keyRouteNodeList.indexOf(isFirst ? keyRouteNode.nodes.first : keyRouteNode.nodes.last) == -1) {
    return false;
  }
  return checkKeyRouteNodes(isFirst ? keyRouteNode.nodes.first : keyRouteNode.nodes.last, keyRouteNodeList, isFirst);
}

// NOTE: pre-order
// NOTE: p span 111 img 222 video source 333 video source 444 555 span video source 666
void preorderTraversalNTree(dom.Node node, {TraversalOperation f = checkNodeType}) {
  for (dom.Node childNode in node.nodes) {
    f(childNode);
    preorderTraversalNTree(childNode, f: f);
  }
}

// NOTE: mid-order
// NOTE: 111 img 222 source video 333 source video 444 span 555 source video 666 span p
void midorderTraversalNTree(dom.Node node, {TraversalOperation f = checkNodeType}) {
  for (dom.Node childNode in node.nodes) {
    midorderTraversalNTree(childNode, f: f);
    f(childNode);
  }
}

// NOTE: breadth-first traversal  
// NOTE: p span 555 span 111 img 222 video 333 444 source source video 666 source
void breadthFirstTraversalNTree(dom.Node node, {TraversalOperation f = checkNodeType}) {
  for (dom.Node childNode in node.nodes) {
    f(childNode);
  }
  for (dom.Node childNode in node.nodes) {
    breadthFirstTraversalNTree(childNode, f: f);
  }
}

// NOTE: 基于广度优先遍历的 N 叉树关键路径剪枝算法（引用传递方式）
void removeNodeInBreadthFirstTraversalNTree(dom.Node node, int deepLevel, List<dom.Node> keyNodeRouteLeft, List<dom.Node> keyNodeRouteRight) {
  // print('TEST: 裁剪节点：');
  // checkNodeType(node);
  
  // NOTE: 跳过叶子节点和关键节点（用关键路径的第一个节点当作关键节点）
  if ((!node.hasChildNodes()) ||
      (keyNodeRouteLeft != null && keyNodeRouteLeft.isNotEmpty && keyNodeRouteLeft.first == node) ||
      (keyNodeRouteRight != null && keyNodeRouteRight.isNotEmpty && keyNodeRouteRight.first == node)
  ) {
    return;
  }
  
  // NOTE: 获取左边界
  int leftBoundary = 0;
  if (keyNodeRouteLeft != null && deepLevel < keyNodeRouteLeft.length && node.nodes.indexOf(keyNodeRouteLeft[keyNodeRouteLeft.length - deepLevel - 1]) != -1) {
    leftBoundary = node.nodes.indexOf(keyNodeRouteLeft[keyNodeRouteLeft.length - deepLevel - 1]);
    // NOTE: 如果关键路径节点的最后一个子节点也是关键路径节点或者关键路径节点就是关键节点，则左边界+1
    if (checkKeyRouteNodes(keyNodeRouteLeft[keyNodeRouteLeft.length - deepLevel - 1], keyNodeRouteLeft, false)) {
      leftBoundary++;
    }
  }
  // print('TEST: 左边界：$leftBoundary');

  // NOTE: 获取右边界
  int rightBoundary = node.nodes.length;
  if (keyNodeRouteRight != null && deepLevel < keyNodeRouteRight.length && node.nodes.indexOf(keyNodeRouteRight[keyNodeRouteRight.length - deepLevel - 1]) != -1) {
    rightBoundary = node.nodes.indexOf(keyNodeRouteRight[keyNodeRouteRight.length - deepLevel - 1]);
    // NOTE: 如果关键路径节点的第一个子节点也是关键路径节点或者关键路径节点就是关键节点，则右边界-1
    if (checkKeyRouteNodes(keyNodeRouteRight[keyNodeRouteRight.length - deepLevel - 1], keyNodeRouteRight, true)) {
      rightBoundary--;
    }
  }
  // print('TEST: 右边界：$rightBoundary');
  
  List<dom.Node> removeNodeList = new List<dom.Node>();

  // NOTE: 获取左支裁剪节点（开区间）
  for (int leftIndex = 0; leftIndex < leftBoundary; ++leftIndex) {
    removeNodeList.add(node.nodes[leftIndex]);
  }

  // NOTE: 获取右支裁剪节点（开区间）
  for (int rightIndex = rightBoundary + 1; rightIndex < node.nodes.length; ++rightIndex) {
    removeNodeList.add(node.nodes[rightIndex]);
  }

  // NOTE: 剪枝
  for (var removeNode in removeNodeList) {
    removeNode.remove();
  }

  // NOTE: 深度+1
  deepLevel++;

  for (dom.Node childNode in node.nodes) {
    removeNodeInBreadthFirstTraversalNTree(childNode, deepLevel, keyNodeRouteLeft, keyNodeRouteRight);
  }
}