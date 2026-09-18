import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register, login, userExists, changePassword } from '../src/auth.js';

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

test('changePassword succeeds with the correct old password and a valid new password', () => {
  register('rudi', 'oldpassword1');
  assert.equal(changePassword('rudi', 'oldpassword1', 'newpassword1'), true);
});

test('changePassword makes the old password stop working and the new password work', () => {
  register('dewi', 'oldpassword1');
  changePassword('dewi', 'oldpassword1', 'newpassword1');
  assert.equal(login('dewi', 'oldpassword1'), false);
  assert.equal(login('dewi', 'newpassword1'), true);
});

test('changePassword rejects a wrong old password', () => {
  register('agus', 'correctpass1');
  assert.throws(() => changePassword('agus', 'wrongpass1', 'newpassword1'), /incorrect|invalid|wrong/i);
  assert.equal(login('agus', 'correctpass1'), true);
});

test('changePassword rejects an unregistered username', () => {
  assert.throws(() => changePassword('ghost', 'whatever1', 'newpassword1'), /not found|does not exist|no user/i);
});

test('changePassword rejects a new password shorter than 8 characters', () => {
  register('tono', 'correctpass1');
  assert.throws(() => changePassword('tono', 'correctpass1', 'short'), /at least 8 characters/);
  assert.equal(login('tono', 'correctpass1'), true);
});

test('changePassword rejects an empty new password', () => {
  register('lina', 'correctpass1');
  assert.throws(() => changePassword('lina', 'correctpass1', ''), /at least 8 characters/);
});
