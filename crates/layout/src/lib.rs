//! Square Control core: pure window geometry. No clock, no I/O, no OS type.
//!
//! Coordinates are global logical points with a top-left origin (the space AX speaks), so the
//! platform adapter converts once and the core never knows which OS it serves.

use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    fn is_valid(&self) -> bool {
        [self.x, self.y, self.width, self.height]
            .iter()
            .all(|value| value.is_finite())
            && self.width >= 0.0
            && self.height >= 0.0
    }

    fn intersection_area(&self, other: &Rect) -> f64 {
        let width = (self.x + self.width).min(other.x + other.width) - self.x.max(other.x);
        let height = (self.y + self.height).min(other.y + other.height) - self.y.max(other.y);
        if width > 0.0 && height > 0.0 {
            width * height
        } else {
            0.0
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Screen {
    pub frame: Rect,
    /// Frame minus the menu bar, the Dock and any reserved strip.
    pub visible: Rect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    LeftHalf,
}

/// What the adapter must read before `resolve`, so it never reads more than the action needs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Needs {
    pub focused_window_frame: bool,
    pub screens: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub window: Rect,
    /// Index 0 is the main screen; it receives windows that touch no screen.
    pub screens: Vec<Screen>,
}

/// A request, not a state: the frame the app ends up with is observed afterwards.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Plan {
    pub frame: Rect,
    pub screen_index: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResolveError {
    NoScreen,
    InvalidGeometry,
}

/// Opaque handle from the adapter's session table; never a title or an OS identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WindowHandle(pub u64);

/// Frames read back from the system before and after an action.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Observation {
    pub window: WindowHandle,
    pub before: Rect,
    pub after: Rect,
}

pub const HISTORY_PER_WINDOW: usize = 20;

/// Undo history as a value, in memory only: a persisted history would be an activity log.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct History {
    frames: HashMap<WindowHandle, Vec<Rect>>,
}

impl History {
    pub fn len(&self, window: WindowHandle) -> usize {
        self.frames.get(&window).map_or(0, Vec::len)
    }

    /// Rebuilds a history from recorded frames (oldest first), keeping the per-window bound.
    pub fn from_entries(entries: Vec<(WindowHandle, Vec<Rect>)>) -> Self {
        let frames = entries
            .into_iter()
            .filter(|(_, frames)| !frames.is_empty())
            .map(|(window, mut frames)| {
                let excess = frames.len().saturating_sub(HISTORY_PER_WINDOW);
                frames.drain(..excess);
                (window, frames)
            })
            .collect();
        Self { frames }
    }
}

/// Recorded frames of one window, oldest first.
pub fn frames(history: &History, window: WindowHandle) -> Vec<Rect> {
    history.frames.get(&window).cloned().unwrap_or_default()
}

pub fn requirements(action: Action) -> Needs {
    match action {
        Action::LeftHalf => Needs {
            focused_window_frame: true,
            screens: true,
        },
    }
}

pub fn resolve(action: Action, snapshot: &Snapshot) -> Result<Plan, ResolveError> {
    if !snapshot.window.is_valid()
        || snapshot
            .screens
            .iter()
            .any(|screen| !screen.frame.is_valid() || !screen.visible.is_valid())
    {
        return Err(ResolveError::InvalidGeometry);
    }
    let (screen_index, screen) = target_screen(snapshot)?;
    let visible = screen.visible;
    let frame = match action {
        // Floored so that an odd or fractional width never exceeds the visible frame.
        Action::LeftHalf => Rect {
            x: visible.x,
            y: visible.y,
            width: (visible.width / 2.0).floor(),
            height: visible.height,
        },
    };
    let screen_index = u32::try_from(screen_index).map_err(|_| ResolveError::InvalidGeometry)?;
    Ok(Plan {
        frame,
        screen_index,
    })
}

/// Largest intersection with the screen frame; ties and windows outside every screen keep the
/// earliest screen, so the choice is deterministic.
fn target_screen(snapshot: &Snapshot) -> Result<(usize, &Screen), ResolveError> {
    let mut best: Option<(usize, &Screen, f64)> = None;
    for (index, screen) in snapshot.screens.iter().enumerate() {
        let area = screen.frame.intersection_area(&snapshot.window);
        match best {
            Some((_, _, best_area)) if area <= best_area => {}
            _ => best = Some((index, screen, area)),
        }
    }
    best.map(|(index, screen, _)| (index, screen))
        .ok_or(ResolveError::NoScreen)
}

pub fn commit(mut history: History, observation: Observation) -> History {
    if observation.before == observation.after {
        return history;
    }
    let frames = history.frames.entry(observation.window).or_default();
    frames.push(observation.before);
    if frames.len() > HISTORY_PER_WINDOW {
        frames.remove(0);
    }
    history
}

pub fn undo_target(history: &History, window: WindowHandle) -> Option<Rect> {
    history
        .frames
        .get(&window)
        .and_then(|frames| frames.last().copied())
}
