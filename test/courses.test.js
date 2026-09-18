import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  listCourses,
  getCourse,
  enrollStudent,
  unenrollStudent,
  getEnrollmentCount,
} from '../src/courses.js';

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

test('unenrollStudent decreases the enrollment count by 1', () => {
  enrollStudent('js-101', 'Ani');
  const before = getEnrollmentCount('js-101');
  const after = unenrollStudent('js-101', 'Ani');
  assert.equal(after, before - 1);
  assert.equal(getEnrollmentCount('js-101'), before - 1);
});

test('unenrollStudent throws for an unknown course', () => {
  assert.throws(() => unenrollStudent('nope-101', 'Ani'), /Course not found/);
});

test('unenrollStudent throws when the student is not enrolled in the course', () => {
  assert.throws(
    () => unenrollStudent('py-101', 'TidakPernahDaftar'),
    /not enrolled/i,
  );
});

test('unenrollStudent only removes the specified student, leaving others enrolled', () => {
  enrollStudent('py-101', 'Citra');
  enrollStudent('py-101', 'Dewi');
  const before = getEnrollmentCount('py-101');

  unenrollStudent('py-101', 'Citra');

  assert.equal(getEnrollmentCount('py-101'), before - 1);
});

test('unenrollStudent throws if the same student unenrolls twice', () => {
  enrollStudent('sql-101', 'Eka');
  unenrollStudent('sql-101', 'Eka');

  assert.throws(() => unenrollStudent('sql-101', 'Eka'), /not enrolled/i);
});
