import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register, login, userExists } from '../src/auth.js';

test('register creates a new user', () => {
  const username = register('budi', 'password123');
  assert.equal(username, 'budi');
  assert.equal(userExists('budi'), true);
});

test('register rejects a username that is already taken', () => {
  register('siti', 'password123');
  assert.throws(() => register('siti', 'anotherpass'), /already taken/);
});

test('register rejects a password shorter than 8 characters', () => {
  assert.throws(() => register('andi', 'short'), /at least 8 characters/);
});

test('login succeeds with matching username and password', () => {
  register('joko', 'correcthorse');
  assert.equal(login('joko', 'correcthorse'), true);
});

test('login fails with a wrong password', () => {
  register('wati', 'correctpass1');
  assert.equal(login('wati', 'wrongpass1'), false);
});

test('login fails for an unregistered username', () => {
  assert.equal(login('nobody', 'whatever1'), false);
});
