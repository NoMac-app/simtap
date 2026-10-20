/**
 * simulator-use's settings, read from the environment: SIMULATOR_USE_<NAME>, or SIMTAP_<NAME> as it was
 * called before simtap was renamed simulator-use (October 20, 2026).
 */
export const setting = (name: string): string | undefined => process.env[`SIMULATOR_USE_${name}`] || process.env[`SIMTAP_${name}`] || undefined;
