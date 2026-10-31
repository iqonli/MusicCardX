# 标题格式解析

语法：%字段%、[条件内容]、$函数(参数)、单引号字面量、双单引号、//行注释、嵌套。字段名不区分大小写，支持列表字段。条件使用字段/函数的布尔结果，不能将字符串0误判为字段不存在。if/if2/if3/ifequal/ifgreater/iflonger惰性求值。

函数：

abs, add, and, caps, caps2, char, crlf, cut, date, day_of_month, directory, directory_path, div, ext, filename, filename_ext, get, greater, if, if2, if3, ifequal, ifgreater, iflonger, info, insert, left, len, len2, lower, max, meta, meta_num, meta_sep, meta_test, min, mod, month, mul, muldiv, not, num, or, pad, pad_right, put, puts, repeat, replace, right, select, strchr, strcmp, stricmp, strrchr, strstr, sub, substr, tab, time, trim, upper, xor, year

本地输入不包含的宿主字段无法自动获得；不支持的函数抛出明确错误。未宣称与foobar2000完整SDK逐函数等价。内部递归深度限制24，部分产生长字符串的函数限制输出长度。

音频输入补充：1.3.3兼容更多track编号Tag写法；仍将音轨编号与总曲目数分别保存为tracknumber、totaltracks，由现有标题格式表达式排版。
