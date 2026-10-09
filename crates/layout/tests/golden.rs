//! Golden vectors shared with the Swift side (NFR-Q1). Comparison is on the f64 bit pattern.

use layout::{resolve, Action, Rect, ResolveError, Screen, Snapshot};

const VECTORS: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../golden/vectors.v1.txt"
));

#[derive(Debug)]
enum Expected {
    Ok(Rect, u32),
    Err(ResolveError),
}

fn parse_number(token: Option<&str>, id: &str) -> Result<f64, String> {
    let token = token.ok_or_else(|| format!("{id}: missing number"))?;
    token
        .parse::<f64>()
        .map_err(|error| format!("{id}: {token}: {error}"))
}

fn parse_rect<'a>(tokens: &mut impl Iterator<Item = &'a str>, id: &str) -> Result<Rect, String> {
    Ok(Rect {
        x: parse_number(tokens.next(), id)?,
        y: parse_number(tokens.next(), id)?,
        width: parse_number(tokens.next(), id)?,
        height: parse_number(tokens.next(), id)?,
    })
}

fn parse_line(line: &str) -> Result<(String, Action, Snapshot, Expected), String> {
    let mut tokens = line.split(' ');
    let id = tokens.next().ok_or("empty line")?.to_owned();
    let action = match tokens.next() {
        Some("left_half") => Action::LeftHalf,
        other => return Err(format!("{id}: unknown action {other:?}")),
    };
    let window = parse_rect(&mut tokens, &id)?;
    let count = parse_number(tokens.next(), &id)? as usize;
    let mut screens = Vec::with_capacity(count);
    for _ in 0..count {
        let frame = parse_rect(&mut tokens, &id)?;
        let visible = parse_rect(&mut tokens, &id)?;
        screens.push(Screen { frame, visible });
    }
    let expected = match tokens.next() {
        Some("ok") => {
            let frame = parse_rect(&mut tokens, &id)?;
            Expected::Ok(frame, parse_number(tokens.next(), &id)? as u32)
        }
        Some("err") => match tokens.next() {
            Some("NoScreen") => Expected::Err(ResolveError::NoScreen),
            Some("InvalidGeometry") => Expected::Err(ResolveError::InvalidGeometry),
            other => return Err(format!("{id}: unknown error {other:?}")),
        },
        other => return Err(format!("{id}: unknown expectation {other:?}")),
    };
    if let Some(extra) = tokens.next() {
        return Err(format!("{id}: trailing token {extra}"));
    }
    Ok((id, action, Snapshot { window, screens }, expected))
}

fn bits(rect: &Rect) -> [u64; 4] {
    [
        rect.x.to_bits(),
        rect.y.to_bits(),
        rect.width.to_bits(),
        rect.height.to_bits(),
    ]
}

#[test]
fn golden_vectors_hold_bit_for_bit() {
    let mut executed = 0usize;
    let mut failures = Vec::new();
    for line in VECTORS
        .lines()
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
    {
        let (id, action, snapshot, expected) = match parse_line(line) {
            Ok(parsed) => parsed,
            Err(error) => {
                failures.push(format!("unreadable vector: {error}"));
                continue;
            }
        };
        executed += 1;
        let actual = resolve(action, &snapshot);
        let holds = match (&expected, &actual) {
            (Expected::Ok(frame, index), Ok(plan)) => {
                bits(frame) == bits(&plan.frame) && *index == plan.screen_index
            }
            (Expected::Err(error), Err(actual_error)) => error == actual_error,
            _ => false,
        };
        if !holds {
            failures.push(format!("{id}: expected {expected:?}, got {actual:?}"));
        }
    }
    println!(
        "golden vectors executed: {executed}, failed: {}",
        failures.len()
    );
    assert!(executed > 0, "no golden vector executed");
    assert!(failures.is_empty(), "{failures:#?}");
}
