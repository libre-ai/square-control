//! UniFFI bridge over the `layout` core: pure functions and value records only (no object,
//! no trait, no callback), so that the bridge stays out of UniFFI issue #2448.

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiScreen {
    pub frame: FfiRect,
    pub visible: FfiRect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiAction {
    LeftHalf,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FfiNeeds {
    pub focused_window_frame: bool,
    pub screens: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiSnapshot {
    pub window: FfiRect,
    pub screens: Vec<FfiScreen>,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiPlan {
    pub frame: FfiRect,
    pub screen_index: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Error)]
pub enum FfiResolveError {
    NoScreen,
    InvalidGeometry,
}

impl std::fmt::Display for FfiResolveError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Literal messages only: no geometry or window data leaves the core in an error.
        formatter.write_str(match self {
            Self::NoScreen => "no screen",
            Self::InvalidGeometry => "invalid geometry",
        })
    }
}

impl std::error::Error for FfiResolveError {}

/// History crosses the bridge as a plain list of recorded frames per window handle, so the
/// Swift side holds it as a value and no stateful object exists in the bridge.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiHistoryEntry {
    pub window: u64,
    pub frames: Vec<FfiRect>,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiObservation {
    pub window: u64,
    pub before: FfiRect,
    pub after: FfiRect,
}

impl From<FfiRect> for layout::Rect {
    fn from(rect: FfiRect) -> Self {
        Self {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
        }
    }
}

impl From<layout::Rect> for FfiRect {
    fn from(rect: layout::Rect) -> Self {
        Self {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
        }
    }
}

impl From<FfiAction> for layout::Action {
    fn from(action: FfiAction) -> Self {
        match action {
            FfiAction::LeftHalf => Self::LeftHalf,
        }
    }
}

#[uniffi::export]
pub fn requirements(action: FfiAction) -> FfiNeeds {
    let needs = layout::requirements(action.into());
    FfiNeeds {
        focused_window_frame: needs.focused_window_frame,
        screens: needs.screens,
    }
}

#[uniffi::export]
pub fn resolve(action: FfiAction, snapshot: FfiSnapshot) -> Result<FfiPlan, FfiResolveError> {
    let snapshot = layout::Snapshot {
        window: snapshot.window.into(),
        screens: snapshot
            .screens
            .into_iter()
            .map(|screen| layout::Screen {
                frame: screen.frame.into(),
                visible: screen.visible.into(),
            })
            .collect(),
    };
    layout::resolve(action.into(), &snapshot)
        .map(|plan| FfiPlan {
            frame: plan.frame.into(),
            screen_index: plan.screen_index,
        })
        .map_err(|error| match error {
            layout::ResolveError::NoScreen => FfiResolveError::NoScreen,
            layout::ResolveError::InvalidGeometry => FfiResolveError::InvalidGeometry,
        })
}

fn to_core(entries: Vec<FfiHistoryEntry>) -> layout::History {
    layout::History::from_entries(
        entries
            .into_iter()
            .map(|entry| {
                (
                    layout::WindowHandle(entry.window),
                    entry.frames.into_iter().map(layout::Rect::from).collect(),
                )
            })
            .collect(),
    )
}

#[uniffi::export]
pub fn commit(history: Vec<FfiHistoryEntry>, observation: FfiObservation) -> Vec<FfiHistoryEntry> {
    let mut windows: Vec<u64> = history.iter().map(|entry| entry.window).collect();
    if !windows.contains(&observation.window) {
        windows.push(observation.window);
    }
    let core = layout::commit(
        to_core(history),
        layout::Observation {
            window: layout::WindowHandle(observation.window),
            before: observation.before.into(),
            after: observation.after.into(),
        },
    );
    windows
        .into_iter()
        .map(|window| FfiHistoryEntry {
            window,
            frames: layout::frames(&core, layout::WindowHandle(window))
                .into_iter()
                .map(FfiRect::from)
                .collect(),
        })
        .filter(|entry| !entry.frames.is_empty())
        .collect()
}

#[uniffi::export]
pub fn undo_target(history: Vec<FfiHistoryEntry>, window: u64) -> Option<FfiRect> {
    layout::undo_target(&to_core(history), layout::WindowHandle(window)).map(FfiRect::from)
}
