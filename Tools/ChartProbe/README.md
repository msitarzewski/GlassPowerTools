# ChartProbe

A throwaway macOS binary that renders one Swift `Chart` through `ImageRenderer` to a PNG, so a
chart layout question can be answered on this machine in seconds instead of an install per
attempt. It found the macOS 27.2 categorical-axis change on its first run (2026-09-21).

    swiftc -O -parse-as-library -o /tmp/probe Tools/ChartProbe/main.swift
    /tmp/probe /tmp/chart.png [aligned|extended|inset]

Edit the `Probe` view to the chart in question; it is not part of any target and never ships.
