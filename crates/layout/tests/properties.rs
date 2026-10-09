//! Core invariants of section 7.1 (spec v2), as properties.

use layout::{
    commit, resolve, undo_target, Action, History, Observation, Rect, Screen, Snapshot,
    WindowHandle,
};
use proptest::prelude::*;

fn finite_rect(max: f64) -> impl Strategy<Value = Rect> {
    (-max..max, -max..max, 1.0..max, 1.0..max).prop_map(|(x, y, width, height)| Rect {
        x,
        y,
        width,
        height,
    })
}

/// Real displays never overlap: screens are laid side by side, left to right, each with its
/// own vertical offset and menu-bar height.
fn screens() -> impl Strategy<Value = Vec<Screen>> {
    prop::collection::vec(
        (
            -2000.0..2000.0f64,
            200.0..6000.0f64,
            200.0..4000.0f64,
            0.0..60.0f64,
        ),
        1..4,
    )
    .prop_map(|specs| {
        let mut next_x = -3000.0;
        specs
            .into_iter()
            .map(|(y, width, height, menu)| {
                let x = next_x;
                next_x += width;
                Screen {
                    frame: Rect {
                        x,
                        y,
                        width,
                        height,
                    },
                    visible: Rect {
                        x,
                        y: y + menu,
                        width,
                        height: height - menu,
                    },
                }
            })
            .collect()
    })
}

fn contains(outer: &Rect, inner: &Rect) -> bool {
    inner.x >= outer.x
        && inner.y >= outer.y
        && inner.x + inner.width <= outer.x + outer.width
        && inner.y + inner.height <= outer.y + outer.height
}

proptest! {
    #[test]
    fn the_plan_is_inside_the_visible_frame_of_its_screen(
        window in finite_rect(8000.0),
        screens in screens(),
    ) {
        let snapshot = Snapshot { window, screens: screens.clone() };
        let plan = resolve(Action::LeftHalf, &snapshot);
        prop_assert!(plan.is_ok());
        if let Ok(plan) = plan {
            let target = &screens[plan.screen_index as usize];
            prop_assert!(contains(&target.visible, &plan.frame));
        }
    }

    #[test]
    fn resolve_is_idempotent(
        window in finite_rect(8000.0),
        screens in screens(),
    ) {
        let first = resolve(Action::LeftHalf, &Snapshot { window, screens: screens.clone() });
        prop_assert!(first.is_ok());
        if let Ok(first) = first {
            let second = resolve(Action::LeftHalf, &Snapshot { window: first.frame, screens });
            prop_assert_eq!(second, Ok(first));
        }
    }

    #[test]
    fn undo_after_commit_returns_the_observed_before(
        window_id in any::<u64>(),
        before in finite_rect(8000.0),
        after in finite_rect(8000.0),
    ) {
        prop_assume!(before != after);
        let window = WindowHandle(window_id);
        let history = commit(History::default(), Observation { window, before, after });
        prop_assert_eq!(undo_target(&history, window), Some(before));
    }
}
