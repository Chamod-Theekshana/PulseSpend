/**
 * Shared security constants so hashing strength is consistent everywhere
 * (previously the primary signup path used cost 10 while the rest used 12).
 */
export const BCRYPT_ROUNDS = 12;
