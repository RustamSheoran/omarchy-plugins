#!/usr/bin/env python3
import sys
import os
import json
from datetime import datetime, timedelta

STATE_FILE = os.path.expanduser("~/.config/omarchy/meds-state.json")

def get_cycle_dates(now):
    # Pill 1 cycle resets at 05:00 each morning
    if now.hour >= 5:
        p1_date = now.date().isoformat()
    else:
        p1_date = (now - timedelta(days=1)).date().isoformat()

    # Pill 2 cycle is 17:00 (5 PM) to 05:00 (5 AM)
    if now.hour >= 17:
        p2_date = now.date().isoformat()
    else:
        p2_date = (now - timedelta(days=1)).date().isoformat()

    return p1_date, p2_date

def load_state():
    now = datetime.now()
    p1_date, p2_date = get_cycle_dates(now)

    state = {
        "mag1": False,
        "mag2": False,
        "b12_1": False,
        "b12_2": False,
        "date_pill1": p1_date,
        "date_pill2": p2_date
    }

    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                saved = json.load(f)
            # Check for daily cycle rollover
            if saved.get("date_pill1") == p1_date:
                state["mag1"] = bool(saved.get("mag1", False))
                state["b12_1"] = bool(saved.get("b12_1", False))
            if saved.get("date_pill2") == p2_date:
                state["mag2"] = bool(saved.get("mag2", False))
                state["b12_2"] = bool(saved.get("b12_2", False))
        except Exception:
            pass

    return state

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def compute_payload(state):
    now = datetime.now()
    hour = now.hour

    # Pill 1: Before 5:00 PM (5:00 AM - 17:00)
    # Pill 2: 5:00 PM to 5:00 AM (17:00 - 5:00)
    is_pill2_window = (hour >= 17 or hour < 5)

    if is_pill2_window:
        alert = not (state["mag2"] and state["b12_2"])
        window = "pill2"
        window_label = "Evening Dose (5:00 PM – 5:00 AM)"
        due_pills = []
        if not state["mag2"]: due_pills.append("Magnesium 2")
        if not state["b12_2"]: due_pills.append("B12 2")
    else:
        alert = not (state["mag1"] and state["b12_1"])
        window = "pill1"
        window_label = "Morning Dose (Before 5:00 PM)"
        due_pills = []
        if not state["mag1"]: due_pills.append("Magnesium 1")
        if not state["b12_1"]: due_pills.append("B12 1")

    p1_taken = int(state["mag1"]) + int(state["b12_1"])
    p2_taken = int(state["mag2"]) + int(state["b12_2"])
    total_taken = p1_taken + p2_taken

    return {
        "mag1": state["mag1"],
        "mag2": state["mag2"],
        "b12_1": state["b12_1"],
        "b12_2": state["b12_2"],
        "alert": alert,
        "active_window": window,
        "window_label": window_label,
        "due_count": len(due_pills),
        "due_summary": ", ".join(due_pills) if due_pills else "All Taken!",
        "pill1_taken": p1_taken,
        "pill2_taken": p2_taken,
        "total_taken": total_taken
    }

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "get"
    state = load_state()

    if action == "set" and len(sys.argv) >= 4:
        pill_key = sys.argv[2]
        val = sys.argv[3].lower() in ["true", "1", "yes"]
        if pill_key in state:
            state[pill_key] = val
            save_state(state)
    elif action == "toggle" and len(sys.argv) >= 3:
        pill_key = sys.argv[2]
        if pill_key in state:
            state[pill_key] = not state[pill_key]
            save_state(state)
    elif action == "reset":
        state["mag1"] = False
        state["mag2"] = False
        state["b12_1"] = False
        state["b12_2"] = False
        save_state(state)

    print(json.dumps(compute_payload(state)))

if __name__ == "__main__":
    main()
