# Workforce Management Block Scheduler

This Jupyter Notebook automates **contact center scheduling** by generating agent shifts, lunch breaks, and two additional breaks (BreakA, BreakB) for a specified week (e.g., April 21–28, 2025). It integrates with **SQL databases** to retrieve agent schedules, applies **collision avoidance** for breaks, handles **overnight shifts**, and respects **blocked dates** (e.g., holidays). Key features include:

Built with **pandas**, **pyodbc**, **numpy**, and **jinja2**, this tool supports **workforce management teams**, **analysts**, and **operations leadership** in optimizing agent schedules. It processes large datasets (e.g., 2624 shifts) and supports client-specific overrides.


Key Features
Automated Scheduling: Generates daily shifts from weekly patterns, handling overnight shifts and breaks.
Collision Avoidance: Uses round-robin lists to prevent overlapping lunch and break times.
Flexible Overrides: Supports agent-specific overrides for lunch, breaks, and full schedules.
Conflict Resolution: Checks for and excludes overlapping or previously scheduled shifts.
Blocked Date Handling: Respects client-specific blocked dates, including midnight shift adjustments.
Scalability: Processes large datasets with efficient DataFrame operations.

Use Cases
Workforce Management: Automates weekly scheduling for contact center agents.
Shift Planning: Optimizes lunch and break assignments to meet SLA requirements.
Conflict Management: Ensures new schedules do not overlap with existing ones.
Holiday Planning: Excludes blocked dates to avoid scheduling on holidays or special events.
Reporting: Provides detailed shift data for workforce analytics and planning.

