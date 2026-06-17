#!/usr/bin/env bash
# format.sh — WeChat Work markdown builder for agent-notify

# build_wechat_markdown <event_json>
build_wechat_markdown() {
    local event_json="$1"
    printf '%s' "$event_json" | jq -r '
        def present: . != null and . != "";
        def fc(c; v): "<font color=\"" + c + "\">" + v + "</font>";
        def title_color:
            if (.status_color == "warning") then "warning" else "info" end;
        def note:
            [.model, .hostname] | map(select(. != null and . != "")) | join(" · ");
        def elapsed_line:
            "⏰ **耗时**：" + fc("warning";
                .elapsed +
                (if ((.t_start | present) and (.t_end | present))
                 then "（" + .t_start + "-" + .t_end + "）"
                 else "" end));
        [
            "## " + fc(title_color; (.agent // "Claude Code") + " · " + (.status_label // "")),
            "",
            "🎯 **结论**",
            (.summary // ""),
            "",
            "---",
            "📦 **项目**：" + fc("info"; .project // "unknown")
        ]
        + (if ((.session_task | present) and (.session_task != .last_task)) then
               ["💬 **Session**：" + fc("comment"; .session_task)]
           else [] end)
        + (if (.last_task | present) then
               ["📋 **任务**：" + fc("comment"; .last_task)]
           else [] end)
        + (if (.elapsed | present) then [elapsed_line] else [] end)
        + (if (note != "") then ["💻 " + fc("comment"; note)] else [] end)
        | join("\n")
    '
}
