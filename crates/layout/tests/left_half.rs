//! E0 behaviour of the core, written before the implementation.

use layout::{
    commit, requirements, resolve, undo_target, Action, History, Needs, Observation, Rect,
    ResolveError, Screen, Snapshot, WindowHandle,
};

fn rect(x: f64, y: f64, width: f64, height: f64) -> Rect {
    Rect {
        x,
        y,
        width,
        height,
    }
}

/// The reference machine: 1512 x 982 points, menu bar 33 pt, no Dock reservation.
fn builtin_screen() -> Screen {
    Screen {
        frame: rect(0.0, 0.0, 1512.0, 982.0),
        visible: rect(0.0, 33.0, 1512.0, 949.0),
    }
}

#[test]
fn left_half_needs_the_focused_window_frame_and_the_screens() {
    assert_eq!(
        requirements(Action::LeftHalf),
        Needs {
            focused_window_frame: true,
            screens: true
        }
    );
}

#[test]
fn left_half_takes_the_left_half_of_the_visible_frame() {
    let snapshot = Snapshot {
        window: rect(300.0, 200.0, 800.0, 600.0),
        screens: vec![builtin_screen()],
    };
    let plan = resolve(Action::LeftHalf, &snapshot);
    assert_eq!(
        plan.map(|p| (p.frame, p.screen_index)),
        Ok((rect(0.0, 33.0, 756.0, 949.0), 0))
    );
}

#[test]
fn an_odd_visible_width_is_floored_so_the_plan_never_leaves_the_visible_frame() {
    let screen = Screen {
        frame: rect(0.0, 0.0, 1513.0, 982.0),
        visible: rect(0.0, 25.0, 1513.0, 957.0),
    };
    let snapshot = Snapshot {
        window: rect(10.0, 40.0, 100.0, 100.0),
        screens: vec![screen],
    };
    let plan = resolve(Action::LeftHalf, &snapshot).map(|p| p.frame);
    assert_eq!(plan, Ok(rect(0.0, 25.0, 756.0, 957.0)));
}

#[test]
fn the_target_screen_is_the_one_with_the_largest_intersection() {
    let left = builtin_screen();
    let right = Screen {
        frame: rect(1512.0, -200.0, 1920.0, 1080.0),
        visible: rect(1512.0, -175.0, 1920.0, 1055.0),
    };
    // 112 pt on the left screen, 688 pt on the right one.
    let snapshot = Snapshot {
        window: rect(1400.0, 100.0, 800.0, 500.0),
        screens: vec![left, right],
    };
    let plan = resolve(Action::LeftHalf, &snapshot);
    assert_eq!(
        plan.map(|p| (p.frame, p.screen_index)),
        Ok((rect(1512.0, -175.0, 960.0, 1055.0), 1))
    );
}

#[test]
fn a_window_outside_every_screen_goes_to_the_first_screen() {
    let snapshot = Snapshot {
        window: rect(-5000.0, -5000.0, 300.0, 300.0),
        screens: vec![builtin_screen()],
    };
    assert_eq!(
        resolve(Action::LeftHalf, &snapshot).map(|p| p.screen_index),
        Ok(0)
    );
}

#[test]
fn no_screen_is_an_error_not_a_guess() {
    let snapshot = Snapshot {
        window: rect(0.0, 0.0, 10.0, 10.0),
        screens: vec![],
    };
    assert_eq!(
        resolve(Action::LeftHalf, &snapshot),
        Err(ResolveError::NoScreen)
    );
}

#[test]
fn non_finite_or_negative_geometry_is_rejected() {
    let bad_window = Snapshot {
        window: rect(f64::NAN, 0.0, 10.0, 10.0),
        screens: vec![builtin_screen()],
    };
    assert_eq!(
        resolve(Action::LeftHalf, &bad_window),
        Err(ResolveError::InvalidGeometry)
    );
    let bad_screen = Snapshot {
        window: rect(0.0, 0.0, 10.0, 10.0),
        screens: vec![Screen {
            frame: rect(0.0, 0.0, 10.0, 10.0),
            visible: rect(0.0, 0.0, -1.0, 10.0),
        }],
    };
    assert_eq!(
        resolve(Action::LeftHalf, &bad_screen),
        Err(ResolveError::InvalidGeometry)
    );
}

#[test]
fn commit_records_the_observed_frames_and_undo_returns_the_observed_before() {
    let window = WindowHandle(7);
    let before = rect(300.0, 200.0, 800.0, 600.0);
    // The app adjusted the planned frame: history keeps what was observed, not the plan.
    let after = rect(0.0, 33.0, 750.0, 949.0);
    let history = commit(
        History::default(),
        Observation {
            window,
            before,
            after,
        },
    );
    assert_eq!(undo_target(&history, window), Some(before));
    assert_eq!(undo_target(&history, WindowHandle(8)), None);
}

#[test]
fn commit_without_a_change_records_nothing() {
    let window = WindowHandle(1);
    let frame = rect(0.0, 33.0, 756.0, 949.0);
    let history = commit(
        History::default(),
        Observation {
            window,
            before: frame,
            after: frame,
        },
    );
    assert_eq!(undo_target(&history, window), None);
}

#[test]
fn history_is_bounded_per_window() {
    let window = WindowHandle(3);
    let mut history = History::default();
    for step in 0..(layout::HISTORY_PER_WINDOW + 5) {
        let before = rect(step as f64, 0.0, 100.0, 100.0);
        let after = rect(step as f64 + 0.5, 0.0, 100.0, 100.0);
        history = commit(
            history,
            Observation {
                window,
                before,
                after,
            },
        );
    }
    assert_eq!(history.len(window), layout::HISTORY_PER_WINDOW);
}

#[test]
fn history_round_trips_through_its_frames_and_keeps_its_bound() {
    let window = WindowHandle(9);
    let frames: Vec<Rect> = (0..(layout::HISTORY_PER_WINDOW + 3))
        .map(|step| rect(step as f64, 0.0, 10.0, 10.0))
        .collect();
    let history = History::from_entries(vec![(window, frames.clone())]);
    assert_eq!(layout::frames(&history, window), frames[3..].to_vec());
    assert_eq!(undo_target(&history, window), frames.last().copied());
    assert_eq!(
        layout::frames(&history, WindowHandle(10)),
        Vec::<Rect>::new()
    );
}
