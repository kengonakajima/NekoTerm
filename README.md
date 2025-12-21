<p align="center">
  <img src="icon.png" width="128">
</p>

<h1 align="center">Nekotty</h1>

<p align="center">
SwiftTermベースのmacOS用ターミナルエミュレータ。左ペインにターミナルのツリービューを表示する。
</p>

![Screenshot](ss.png)

## 特徴

- 複数ターミナルを左ペインでプレビュー表示
- カレントディレクトリでプロジェクト別に自動グループ化
- Cmd+数字の2ストロークでターミナル切り替え（Cmd+1-1, Cmd+2-3 など）
- Cmd+上下でターミナル間移動、Cmd+Shift+上下でグループ間移動
- ドラッグ&ドロップで並べ替え

## ビルド

```
make run
```

## キーバインド

| キー | 動作 |
|------|------|
| Cmd+T | 新規タブ |
| Cmd+N | 新規ウィンドウ |
| Cmd+W | タブを閉じる |
| Cmd+K | バッファクリア |
| Cmd+上/下 | ターミナル切り替え |
| Cmd+Shift+上/下 | グループ切り替え |
| Cmd+数字+数字 | グループ内ターミナル選択 |
| Cmd++/- | フォントサイズ変更 |

## 依存

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (ローカルの ../SwiftTerm を参照)
