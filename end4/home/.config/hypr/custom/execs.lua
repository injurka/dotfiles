-- The end-4 shell provides its own Polkit agent.
-- Keep the personal dropdown-terminal daemon available from the first keypress.
hl.on("hyprland.start", function()
    hl.exec_cmd('test -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.pyprland.sock" || "$HOME/.local/state/hyde/python_env/bin/pypr"')
end)
