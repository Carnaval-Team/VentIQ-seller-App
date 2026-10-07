/**
 * Host half of the Execution Monitor bundle.
 *
 * The plugin is a pure Client (browser) plugin: it registers a Conversation
 * View and a compact input-dock strip that read the session's live Trajectory
 * through the standard slot props. Nothing runs in the Host process, so this
 * half only exists because a bundle row must resolve to an importable module.
 */

/** Host plugin body: no Host-side resources are registered. */
export function apply() {}
