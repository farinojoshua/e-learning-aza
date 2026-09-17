import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

const MIN_PASSWORD_LENGTH = 8;

const users = new Map();

function hashPassword(password, salt) {
  return scryptSync(password, salt, 64).toString('hex');
}

export function register(username, password) {
  if (users.has(username)) {
    throw new Error(`Username already taken: ${username}`);
  }
  if (!password || password.length < MIN_PASSWORD_LENGTH) {
    throw new Error(`Password must be at least ${MIN_PASSWORD_LENGTH} characters`);
  }

  const salt = randomBytes(16).toString('hex');
  const passwordHash = hashPassword(password, salt);
  users.set(username, { username, salt, passwordHash });
  return username;
}

export function login(username, password) {
  const user = users.get(username);
  if (!user) {
    return false;
  }

  const candidateHash = hashPassword(password, user.salt);
  const stored = Buffer.from(user.passwordHash, 'hex');
  const candidate = Buffer.from(candidateHash, 'hex');
  if (stored.length !== candidate.length) {
    return false;
  }

  return timingSafeEqual(stored, candidate);
}

export function userExists(username) {
  return users.has(username);
}
