# Atoll 二开跟随上游

本仓库使用 `upstream` 指向官方 Atoll 仓库，`yiduo/notch-offset` 保存意朵的二开改动。

## 同步作者最新功能

先确认当前没有未提交改动，然后执行：

```bash
git fetch upstream dev
git rebase upstream/dev
```

如果出现冲突，优先保留上游同一功能的最新实现，再重新应用水平偏移相关改动。完成后检查：

```bash
git diff upstream/dev...HEAD --stat
git diff --check
```

水平偏移设置保存在 `notchHorizontalOffset`，默认值为 `0`。它只改变主刘海相对于屏幕中心的水平位置，不改变官方扩展接口。
