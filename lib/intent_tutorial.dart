import 'package:flutter/material.dart';

class IntentTutorialPage extends StatelessWidget {
  const IntentTutorialPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('调用教程')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: SelectableText('''请先尝试最简单的方法，从已有的系统长按菜单获取。

点“从长按菜单中选取”，选择“询问ChatGPT”等入口。X会填好目标和详细设置。
给它起一个喜欢的名字，在“测试文本”里写一段话，再点“测试”。点“保存”后，快捷按钮就出现在AI外包页面。
快捷按钮发送当前提示词全文；编辑页的“测试”只发送下面的测试文本。

怎样算成功？

点“测试”后，对应APP打开并显示你填写的测试文本，就成功了。保存后用快捷按钮再试一次，显示当前生成的提示词，说明整条流程已接通。
只打开APP却没有文字，说明目标已打开，但传文本还没接通：展开详细设置，核对Action、MIME和参数。长按菜单入口使用下面的“处理选中文本”示例，分享入口使用“分享文本”示例。
出现权限错误，换成列表中可供外部调用的活动；找不到活动，就重新选取。完全没有跳转，先看页面提示，并检查目标应用是否已安装、启用。
默认开启“打开快捷方式前自动复制”，即使目标APP没有带入文字，也可以直接在它的输入框粘贴。这个选项只负责复制，不会自动替你粘贴或发送。

若要启动其他活动，请打开Activity列表。

搜索应用、包名或活动名称，展开应用后点选活动：
“填入目标Activity”把这个入口带回编辑页。
“启动活动”直接打开这个入口，不附带文本参数。
右侧复制按钮复制完整活动类名。

Activity列表只更改目标。要传入文字，请在“详细设置 不建议编辑”中选择对应的Action和参数。

如果你看到这里还没有解决，看看下面的高级说明。

目标格式

包名/完整Activity类名，例如com.example/com.example.AskActivity。

处理选中文本

Action：android.intent.action.PROCESS_TEXT
MIME：text/plain
参数：
[
  {"key":"android.intent.extra.PROCESS_TEXT","type":"charSequence","value":"{{prompt}}"},
  {"key":"android.intent.extra.PROCESS_TEXT_READONLY","type":"boolean","value":"true"}
]

分享文本

Action：android.intent.action.SEND
MIME：text/plain
参数：
[
  {"key":"android.intent.extra.TEXT","type":"string","value":"{{prompt}}"}
]

参数怎么写

每项包含key、type和value。key是目标应用约定的参数名，value用双引号包住。
{{prompt}}会替换为要发送的全文，也可以写成“请核实：{{prompt}}”。
类型：string是普通文字；charSequence是文本处理入口常用的文字；boolean填true或false；int是32位整数；long是64位整数；double是小数。

排查方法

能打开但没收到文字：核对Action、MIME、参数名和类型。
列表为空：在系统应用信息中打开读取应用列表权限，返回列表刷新。
入口变更：重新从列表选取。
权限错误：选择已启用且可供外部调用的入口。内部活动仍可查看和复制，但普通应用权限不能直接打开。

点“管理”可编辑、复制和删除快捷按钮。调用配置随样式配置保存、导入和导出。
'''),
    ),
  );
}
