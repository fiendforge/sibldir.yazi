-- sibldir: ディレクトリだけを next / prev で巡回する Yazi プラグイン。
--
-- next: 最初の子 → 次の兄弟 → 親の次の兄弟 → 次がなければルート
-- prev: 前の兄弟の最後の子孫 → 親 → ルートなら最後の子へ
--
-- --nosymlink: シンボリックリンクのディレクトリを移動先から除外する。
-- 指定しない場合はリンク先がディレクトリなら候補に含める。

-- 非同期プラグインから現在位置と Yazi の表示設定を安全に取得する。
local get_context = ya.sync(function()
    local pref = cx.active.pref
    return {
        cwd = cx.active.current.cwd,
        show_hidden = pref.show_hidden,
        sort_sensitive = pref.sort_sensitive,
        sort_reverse = pref.sort_reverse,
    }
end)

-- URL は文字列にして比較する（同じパスかどうか）。
local function same_url(a, b)
    return tostring(a) == tostring(b)
end

-- 指定ディレクトリ直下の「ディレクトリ型の項目」を名前順で返す。
-- resolve=false でリンクそのものの属性を取得するのが重要。
-- リンク先がディレクトリかどうかは fs.cha(url, true) で別途調べる。
-- 隠し項目やシンボリックリンクも一旦一覧に残し、移動候補を選ぶ際に除外する。
-- これにより、現在位置がリンクでも兄弟の探索位置を特定できる。
local function list_directories(url, opts)
    local files = fs.read_dir(url, { resolve = false })
    if not files then
        return nil  -- 権限不足など。呼び出し元では「子がない」ものとして扱う。
    end

    local dirs = {}
    for _, file in ipairs(files) do
        local is_link = file.cha.is_link
        local is_dir = file.cha.is_dir

        if is_link then
            -- リンク先の属性を調べ、ディレクトリを指すリンクだけを対象にする。
            local target_cha = fs.cha(file.url, true)
            is_dir = target_cha ~= nil and target_cha.is_dir
        end

        if is_dir then
            dirs[#dirs + 1] = {
                url = file.url,
                name = file.name,
                is_link = is_link,
                is_hidden = file.cha.is_hidden,
                link_to = file.link_to,
            }
        end
    end

    -- 名前でソートする。Yazi の自然順/更新日時順などは再現しない。
    table.sort(dirs, function(a, b)
        local x = opts.sort_sensitive and a.name or a.name:lower()
        local y = opts.sort_sensitive and b.name or b.name:lower()
        if x == y then
            return opts.sort_reverse and a.name > b.name
                or (not opts.sort_reverse and a.name < b.name)
        end
        return opts.sort_reverse and x > y or x < y
    end)

    return dirs
end

-- 移動候補として使えるか確認する。
-- 権限不足で一覧を読めない場合はスキップする。
local function usable(dir, opts)
    if not opts.show_hidden and dir.is_hidden then
        return false
    end
    if dir.is_link then
        if opts.nosymlink then
            return false
        end
        -- リンクを許可する場合も、明らかな自己/親への循環は除外する。
        -- （例: Ubuntu の /usr/bin/X11 -> .）
        if dir.link_to then
            local target = tostring(dir.link_to)
            if target == "." or target == ".." then
                return false
            end
        end
    end
    return fs.read_dir(dir.url, { limit = 1 }) ~= nil
end

-- 指定ディレクトリの最初または最後の「移動可能な子」を探す。
local function child_of(url, opts, step)
    local dirs = list_directories(url, opts)
    if not dirs then
        return nil
    end

    local i = step == 1 and 1 or #dirs
    while i >= 1 and i <= #dirs do
        if usable(dirs[i], opts) then
            return dirs[i]
        end
        i = i + step
    end
    return nil
end

-- 指定ディレクトリの次（step=1）または前（step=-1）の兄弟を探す。
-- 権限がない兄弟や --nosymlink で除外された兄弟は飛ばす。
local function sibling_of(url, opts, step)
    local parent = url.parent
    if not parent then
        return nil
    end

    local dirs = list_directories(parent, opts)
    if not dirs then
        return nil
    end

    for i, dir in ipairs(dirs) do
        if same_url(dir.url, url) then
            local j = i + step
            while j >= 1 and j <= #dirs do
                if usable(dirs[j], opts) then
                    return dirs[j].url
                end
                j = j + step
            end
            break
        end
    end
    return nil
end

-- 逆方向では、前の兄弟の「最後の子孫」まで降りる。
-- 万一の循環に備え、1回の操作で降りる深さに上限を設ける。
-- 完全にリンクを辿らせたくなければ --nosymlink を指定する。
local function last_descendant(url, opts)
    local seen = {}
    for _ = 1, 128 do
        local key = tostring(url)
        if seen[key] then
            break
        end
        seen[key] = true

        local child = child_of(url, opts, -1)
        if not child then
            break
        end

        url = child.url
    end
    return url
end

-- 順方向: 子へ入り、子がなければ次の兄弟を探しながら親へ遡る。
local function sibl_next(current, opts)
    local child = child_of(current, opts, 1)
    if child then
        return child.url
    end

    local dir = current
    while dir.parent do
        local sibling = sibling_of(dir, opts, 1)
        if sibling then
            return sibling
        end
        dir = dir.parent
    end
    return dir  -- すべて見終わったらルートへ。
end

-- 逆方向: 前の兄弟があればその末端へ、なければ親へ。
-- ルートからは最後の子孫へ折り返す。
local function sibl_prev(current, opts)
    if not current.parent then
        return last_descendant(current, opts)
    end

    local sibling = sibling_of(current, opts, -1)
    if sibling then
        return last_descendant(sibling, opts)
    end
    return current.parent
end

return {
    entry = function(self, job)
        local direction = job.args[1]
        if direction ~= "next" and direction ~= "prev" then
            ya.notify({
                title = "sibldir",
                content = "Specify next or prev",
                level = "warn",
                timeout = 3,
            })
            return
        end

        local opts = get_context()
        -- Yazi は --nosymlink を名前付き引数として job.args.nosymlink に入れる。
        opts.nosymlink = job.args.nosymlink == true

        local destination
        if direction == "next" then
            destination = sibl_next(opts.cwd, opts)
        else
            destination = sibl_prev(opts.cwd, opts)
        end

        if destination and not same_url(destination, opts.cwd) then
            ya.emit("cd", { destination })
        end
    end,
}
