const courses = [
  { id: 'js-101', title: 'JavaScript Dasar', capacity: 30 },
  { id: 'py-101', title: 'Python untuk Pemula', capacity: 25 },
  { id: 'sql-101', title: 'SQL Dasar', capacity: 40 },
];

const enrollments = new Map();

export function listCourses() {
  return courses.map((c) => ({ ...c }));
}

export function getCourse(id) {
  return courses.find((c) => c.id === id) ?? null;
}

export function enrollStudent(courseId, studentName) {
  const course = getCourse(courseId);
  if (!course) {
    throw new Error(`Course not found: ${courseId}`);
  }

  const current = enrollments.get(courseId) ?? [];
  if (current.length >= course.capacity) {
    throw new Error(`Course is full: ${courseId}`);
  }

  const updated = [...current, studentName];
  enrollments.set(courseId, updated);
  return updated.length;
}

export function unenrollStudent(courseId, studentName) {
  const course = getCourse(courseId);
  if (!course) {
    throw new Error(`Course not found: ${courseId}`);
  }

  const current = enrollments.get(courseId) ?? [];
  if (!current.includes(studentName)) {
    throw new Error(`Student not enrolled: ${studentName} in ${courseId}`);
  }

  const updated = current.filter((name) => name !== studentName);
  enrollments.set(courseId, updated);
  return updated.length;
}

export function getEnrollmentCount(courseId) {
  return (enrollments.get(courseId) ?? []).length;
}
