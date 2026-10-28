# sibldir.yazi

A [Yazi](https://github.com/sxyazi/yazi) plugin for navigating directories in depth-first order. When a directory contains subdirectories, `next` enters them first, making the plugin useful for systematically traversing an entire directory tree.

### Navigation Example

```text
/
├── A
│   ├── a1
│   └── a2
├── B
│   ├── b1
│   └── b2
└── C
```

Forward traversal (`next`):

```text
/ → A → a1 → a2 → B → b1 → b2 → C → /
```

## Installation

Manual install

Place main.lua in ~/.config/yazi/plugins/sibldir.yazi/

## Usage

Add keybindings to `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = "<C-j>"
run = "plugin sibldir -- next"
desc = "Next directory"

[[mgr.prepend_keymap]]
on = "<C-k>"
run = "plugin sibldir -- prev"
desc = "Previous directory"
```

Use `next` to move forward and `prev` to move backward.

Add `--nosymlink` to either command to skip symbolic links
(for example, `"plugin sibldir -- next --nosymlink"`).

## License

[MIT License](LICENSE)


