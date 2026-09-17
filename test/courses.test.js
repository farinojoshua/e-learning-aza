import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listCourses, getCourse, enrollStudent, getEnrollmentCount } from '../src/courses.js';

test('listCourses returns all seeded courses', () => {
  const courses = listCourses();
  assert.equal(courses.length, 3);
  assert.ok(courses.some((c) => c.id === 'js-101'));
});

test('getCourse finds an existing course by id', () => {
  const course = getCourse('py-101');
  assert.equal(course.title, 'Python untuk Pemula');
});

test('getCourse returns null for an unknown id', () => {
  assert.equal(getCourse('does-not-exist'), null);
});

test('enrollStudent increases the enrollment count', () => {
  const before = getEnrollmentCount('sql-101');
  const after = enrollStudent('sql-101', 'Budi');
  assert.equal(after, before + 1);
});

test('enrollStudent throws for an unknown course', () => {
  assert.throws(() => enrollStudent('nope-101', 'Budi'), /Course not found/);
});
