use anyhow::{Context, Result};
use std::path::Path;

use crate::types::PrefixMap;

/// Parse prefix.yaml file.
/// Format:
/// ```yaml
/// rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
/// rdfs: <http://www.w3.org/2000/01/rdf-schema#>
/// ```
pub fn parse_prefix_yaml(path: &Path) -> Result<PrefixMap> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read prefix.yaml: {}", path.display()))?;

    let mut prefixes = PrefixMap::new();

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        // Format: "prefix: <uri>"
        if let Some((prefix, uri_part)) = line.split_once(':') {
            let prefix = prefix.trim().to_string();
            let uri_part = uri_part.trim();
            // Extract URI from <...>
            if let (Some(start), Some(end)) = (uri_part.find('<'), uri_part.rfind('>')) {
                let uri = uri_part[start + 1..end].to_string();
                prefixes.insert(prefix, uri);
            }
        }
    }

    Ok(prefixes)
}

/// Expand a CURIE (prefix:local) to a full URI using the prefix map.
/// If it's already a full URI (<...>), strip the angle brackets.
/// Returns None if it's neither.
pub fn expand_curie(value: &str, prefixes: &PrefixMap) -> Option<String> {
    let value = value.trim();
    // Full URI in angle brackets
    if value.starts_with('<') && value.ends_with('>') {
        return Some(value[1..value.len() - 1].to_string());
    }
    // CURIE prefix:local
    if let Some((prefix, local)) = value.split_once(':') {
        if let Some(base_uri) = prefixes.get(prefix) {
            return Some(format!("{}{}", base_uri, local));
        }
    }
    None
}

/// Check if a string is a CURIE (prefix:local) with a known prefix.
pub fn is_known_curie(value: &str, prefixes: &PrefixMap) -> bool {
    if let Some((prefix, _)) = value.split_once(':') {
        prefixes.contains_key(prefix)
    } else {
        false
    }
}

/// Check if a string looks like a URI (<...>) or a known CURIE.
pub fn is_uri_like(value: &str, prefixes: &PrefixMap) -> bool {
    let value = value.trim();
    if value.starts_with('<') && value.ends_with('>') {
        return true;
    }
    is_known_curie(value, prefixes)
}
