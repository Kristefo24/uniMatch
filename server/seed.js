// Seed data for UniMatch Gasabo. Ids match the Flutter client (kUniversityIds).
// Universities start with no criteria values (vals: {}) — every numeric
// criterion (tuition, distance, career services, ICT infrastructure,
// reputation, etc.) is entered by real staff via StaffCriteriaScreen,
// never pre-filled with demo numbers.

const DEFAULT_ADMIN = {
  name: 'Kris',
  email: 'kris@unimatch.com',
  password: '123',
  role: 'admin',
};

const DEPARTMENTS = [
  'Business, Economics & Management',
  'Computing, IT & Engineering',
  'Health & Medical Sciences',
  'Education & Social Sciences',
  'Law, Governance & Public Affairs',
  'Arts, Humanities & Communication',
  'Agriculture, Environment & Natural Sciences',
  'Architecture, Construction, Hospitality & Tourism',
];

// Each university: vals carry the criteria the ranking reads. campuses and
// programmes start empty — a university has no data at all (and A2
// graduates see nothing for it: no departments, no programmes) until real
// staff register for it and enter their own campuses and programmes via the
// Staff dashboard. This matches the same "never pre-filled, only real
// staff-entered data" rule already applied to criteria vals above.
const UNIVERSITIES = [
  { id:'uni-uok', abbr:'UoK', name:'University of Kigali', campuses:[], programmes:[], vals:{} },
  { id:'uni-eau', abbr:'EAU', name:'East African University', campuses:[], programmes:[], vals:{} },
  { id:'uni-alu', abbr:'ALU', name:'African Leadership University', campuses:[], programmes:[], vals:{} },
  { id:'uni-auca', abbr:'AUCA', name:'Adventist University of Central Africa', campuses:[], programmes:[], vals:{} },
  { id:'uni-urcmhs', abbr:'UR/CMHS', name:'UR College of Medicine & Health Sciences', campuses:[], programmes:[], vals:{} },
  { id:'uni-ulk', abbr:'ULK', name:'Kigali Independent University', campuses:[], programmes:[], vals:{} },
  { id:'uni-kepler', abbr:'Kepler', name:'Kepler College', campuses:[], programmes:[], vals:{} },
];

// Programmes across all universities (explicit, from each university's programmes list).
function buildProgrammes() {
  const progs = [];
  let n = 1;
  for (const u of UNIVERSITIES) {
    for (const p of (u.programmes || [])) {
      progs.push({ id: `prog-${n++}`, name: p.name, dept: p.dept, campus: p.campus || '',
        years: p.years || null, universityId: u.id });
    }
  }
  return progs;
}

const STAFF_REQUESTS = [
  { id:'req1', name:'Jean Claire U.', email:'jc.uwase@eau.ac.rw', universityId:'uni-eau', status:'pending' },
  { id:'req2', name:'Aline K.', email:'aline.k@uok.ac.rw', universityId:'uni-uok', status:'pending' },
];

// Evaluation criteria the admin can manage. direction: 'cost' (lower better) | 'benefit'.
const CRITERIA = [
  { code:'C01', label:'Annual tuition fee', category:'Financial', direction:'cost' },
  { code:'C02', label:'Scholarship & financial aid', category:'Financial', direction:'benefit' },
  // C03 "Programme availability" and C04 "Faculty qualifications" are
  // intentionally not offered as criteria — programme/department
  // availability is already a hard eligibility filter in POST /rank
  // (db.listProgrammes), so a separate scored criterion for it would be
  // redundant and was never staff-set anyway.
  { code:'C05', label:'Average class size', category:'Academic Quality', direction:'cost' },
  { code:'C06', label:'Graduation / completion rate', category:'Academic Quality', direction:'benefit' },
  { code:'C07', label:'Distance from your home', category:'Location & Accessibility', direction:'cost' },
  { code:'C08', label:'On-campus accommodation', category:'Location & Accessibility', direction:'benefit' },
  { code:'C09', label:'Proximity to public transport', category:'Location & Accessibility', direction:'cost' },
  { code:'C10', label:'Graduate employment rate', category:'Career & Employability', direction:'benefit' },
  { code:'C11', label:'Internship & industry partnerships', category:'Career & Employability', direction:'benefit' },
  { code:'C12', label:'Alumni network strength', category:'Career & Employability', direction:'benefit' },
  { code:'C13', label:'Career services quality', category:'Career & Employability', direction:'benefit' },
  { code:'C14', label:'Library & e-learning resources', category:'Campus Life & Facilities', direction:'benefit' },
  { code:'C15', label:'ICT infrastructure / Wi-Fi', category:'Campus Life & Facilities', direction:'benefit' },
  { code:'C16', label:'Sporting & recreational facilities', category:'Campus Life & Facilities', direction:'benefit' },
  { code:'C17', label:'Health / medical services', category:'Campus Life & Facilities', direction:'benefit' },
  { code:'C18', label:'Student satisfaction score', category:'Campus Life & Facilities', direction:'benefit' },
  { code:'C19', label:'Academic / peer reputation', category:'Institutional Reputation', direction:'benefit' },
  { code:'C20', label:'National ranking position', category:'Institutional Reputation', direction:'cost' },
  { code:'C21', label:'Years of operation', category:'Institutional Reputation', direction:'benefit' },
  { code:'C22', label:'Institutional size', category:'Institutional Reputation', direction:'benefit' },
  { code:'C23', label:'Minimum entry grade', category:'Admission & Eligibility', direction:'cost' },
  // C24 "Required subject combinations" is intentionally not offered as a
  // criterion — eligible combinations are a per-programme StaffCombosScreen
  // setting, not a single scored number, and every university would score
  // identically on it anyway.
  { code:'C25', label:'Religious / cultural affiliation', category:'Personal & Contextual', direction:'benefit' },
  { code:'C26', label:'Mode of study available', category:'Personal & Contextual', direction:'benefit' },
];

// Seeded student accounts so the admin has people to suspend/restore.
const STUDENTS = [
  { id:'stu-amara',  name:'Amara Mukamana', email:'amara@example.com',   home:'Kacyiru, Gasabo' },
  { id:'stu-eric',   name:'Eric Habimana',  email:'eric.h@example.com',  home:'Kimironko, Gasabo' },
  { id:'stu-diane',  name:'Diane Ingabire', email:'diane.i@example.com', home:'Remera, Gasabo' },
  { id:'stu-kevin',  name:'Kevin Niyonzima',email:'kevin.n@example.com', home:'Kinyinya, Gasabo' },
];

function freshStore() {
  return {
    users: [
      { id:'user-admin', ...DEFAULT_ADMIN },
      ...STUDENTS.map(s => ({ id:s.id, name:s.name, email:s.email, password:'123', role:'student', home:s.home, suspended:false })),
    ],
    universities: UNIVERSITIES,
    programmes: buildProgrammes(),
    staffRequests: STAFF_REQUESTS,
    criteria: CRITERIA,
    applications: [],
    shortlists: [],
    ratings: [],
    criteriaSelections: [],
    userLastRanking: {},
  };
}

module.exports = { DEFAULT_ADMIN, DEPARTMENTS, UNIVERSITIES, STAFF_REQUESTS, CRITERIA, STUDENTS, freshStore, buildProgrammes };
