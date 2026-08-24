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

// Each university: vals carry the criteria the ranking reads.
const UNIVERSITIES = [
  { id:'uni-uok', abbr:'UoK', name:'University of Kigali',
    campuses:[
      {name:'Remera Campus', depts:['Business, Economics & Management']},
      {name:'Main Campus', depts:['Computing, IT & Engineering','Education & Social Sciences','Law, Governance & Public Affairs']},
    ],
    programmes:[
      {name:'Public Administration and Local Governance', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Marketing (Hons)', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Supplies and Procurement Management (Hons)', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Economics (Hons)', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Finance (Hons)', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Accounting (Hons)', dept:'Business, Economics & Management', campus:'Remera Campus', years:4},
      {name:'Information Technology (Hons)', dept:'Computing, IT & Engineering', campus:'Main Campus', years:4},
      {name:'Computer Science (Hons)', dept:'Computing, IT & Engineering', campus:'Main Campus', years:4},
      {name:'Business Information Technology (Hons)', dept:'Computing, IT & Engineering', campus:'Main Campus', years:4},
      {name:'Early Childhood Development Education (ECD)', dept:'Education & Social Sciences', campus:'Main Campus', years:4},
      {name:'Law (Hons)', dept:'Law, Governance & Public Affairs', campus:'Main Campus', years:4},
    ],
    vals:{} },

  { id:'uni-eau', abbr:'EAU', name:'East African University',
    campuses:[{name:'Kicukiro Campus', depts:['Arts, Humanities & Communication','Architecture, Construction, Hospitality & Tourism']}],
    programmes:[
      {name:'Theatre & Performing Arts', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Animation & Visual Effects', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Media & Communication', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Film Editing & Post-Production', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Tourism Management', dept:'Architecture, Construction, Hospitality & Tourism', campus:'Kicukiro Campus', years:3},
      {name:'Hotel & Hospitality Management', dept:'Architecture, Construction, Hospitality & Tourism', campus:'Kicukiro Campus', years:3},
      {name:'Leisure Management', dept:'Architecture, Construction, Hospitality & Tourism', campus:'Kicukiro Campus', years:3},
      {name:'Travel & Tourism', dept:'Architecture, Construction, Hospitality & Tourism', campus:'Kicukiro Campus', years:3},
      {name:'Journalism', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Journalism Radio & Television Broadcasting', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
      {name:'Public Relations', dept:'Arts, Humanities & Communication', campus:'Kicukiro Campus', years:3},
    ],
    vals:{} },

  { id:'uni-alu', abbr:'ALU', name:'African Leadership University',
    campuses:[{name:'Bumbogo Campus', depts:['Business, Economics & Management','Computing, IT & Engineering']}],
    programmes:[
      {name:'Entrepreneurial Leadership (BEL)', dept:'Business, Economics & Management', campus:'Bumbogo Campus', years:3},
      {name:'Software Engineering (BSE)', dept:'Computing, IT & Engineering', campus:'Bumbogo Campus', years:3},
      {name:'Information Technology', dept:'Computing, IT & Engineering', campus:'Bumbogo Campus', years:3},
      {name:'Business Information and Technology', dept:'Computing, IT & Engineering', campus:'Bumbogo Campus', years:3},
      {name:'International Business & Trade (IBT)', dept:'Business, Economics & Management', campus:'Bumbogo Campus', years:3},
      {name:'Strategic Management', dept:'Business, Economics & Management', campus:'Bumbogo Campus', years:3},
    ],
    vals:{} },

  { id:'uni-auca', abbr:'AUCA', name:'Adventist University of Central Africa',
    campuses:[
      {name:'Gishushu Campus', depts:['Computing, IT & Engineering']},
      {name:'Masoro Campus', depts:['Business, Economics & Management','Education & Social Sciences','Arts, Humanities & Communication','Health & Medical Sciences']},
    ],
    programmes:[
      {name:'Software Engineering', dept:'Computing, IT & Engineering', campus:'Gishushu Campus', years:4},
      {name:'Information Management', dept:'Computing, IT & Engineering', campus:'Gishushu Campus', years:4},
      {name:'Network & Communication Systems', dept:'Computing, IT & Engineering', campus:'Gishushu Campus', years:4},
      {name:'Marketing', dept:'Business, Economics & Management', campus:'Masoro Campus', years:4},
      {name:'Management', dept:'Business, Economics & Management', campus:'Masoro Campus', years:4},
      {name:'Finance', dept:'Business, Economics & Management', campus:'Masoro Campus', years:4},
      {name:'Accounting', dept:'Business, Economics & Management', campus:'Masoro Campus', years:4},
      {name:'Education Psychology', dept:'Education & Social Sciences', campus:'Masoro Campus', years:4},
      {name:'Literature & Languages', dept:'Education & Social Sciences', campus:'Masoro Campus', years:4},
      {name:'Mathematics & Sciences', dept:'Education & Social Sciences', campus:'Masoro Campus', years:4},
      {name:'Theology', dept:'Arts, Humanities & Communication', campus:'Masoro Campus', years:3},
      {name:'Nursing and Midwifery', dept:'Health & Medical Sciences', campus:'Masoro Campus', years:5},
    ],
    vals:{} },

  { id:'uni-urcmhs', abbr:'UR/CMHS', name:'UR College of Medicine & Health Sciences',
    campuses:[{name:'Remera Campus', depts:['Health & Medical Sciences']}],
    programmes:[
      {name:'Medicine', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Pharmacy', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Nursing', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Midwifery', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Public Health', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Health Promotion', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Dentist', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Dental Surgery', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Medical Laboratory Science', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Radiography', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
      {name:'Nutrition', dept:'Health & Medical Sciences', campus:'Remera Campus', years:5},
    ],
    vals:{} },

  { id:'uni-ulk', abbr:'ULK', name:'Kigali Independent University',
    campuses:[{name:'Gisozi Campus', depts:['Business, Economics & Management','Education & Social Sciences','Law, Governance & Public Affairs','Computing, IT & Engineering']}],
    programmes:[
      {name:'Economics (Hons)', dept:'Business, Economics & Management', campus:'Gisozi Campus', years:4},
      {name:'Finance (Hons)', dept:'Business, Economics & Management', campus:'Gisozi Campus', years:4},
      {name:'Accounting (Hons)', dept:'Business, Economics & Management', campus:'Gisozi Campus', years:4},
      {name:'Rural Development (Hons)', dept:'Business, Economics & Management', campus:'Gisozi Campus', years:4},
      {name:'Management (Hons)', dept:'Business, Economics & Management', campus:'Gisozi Campus', years:4},
      {name:'Development Studies (Hons)', dept:'Education & Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'International Relations (Hons)', dept:'Education & Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Population Studies (Hons)', dept:'Education & Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Sociology (Hons)', dept:'Education & Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Administrative Sciences (Hons)', dept:'Education & Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Administrative Sciences (Hons)', dept:'Law, Governance & Public Affairs', campus:'Gisozi Campus', years:4},
      {name:'Private Law (Hons)', dept:'Law, Governance & Public Affairs', campus:'Gisozi Campus', years:4},
      {name:'Data Science (Hons)', dept:'Computing, IT & Engineering', campus:'Gisozi Campus', years:4},
      {name:'Software Engineering (Hons)', dept:'Computing, IT & Engineering', campus:'Gisozi Campus', years:4},
      {name:'Networking (Hons)', dept:'Computing, IT & Engineering', campus:'Gisozi Campus', years:4},
    ],
    vals:{} },

  { id:'uni-kepler', abbr:'Kepler', name:'Kepler College',
    campuses:[{name:'Kigali Heights Campus', depts:['Business, Economics & Management','Arts, Humanities & Communication']}],
    programmes:[
      {name:'Arts in Project Management', dept:'Business, Economics & Management', campus:'Kigali Heights Campus', years:3},
      {name:'Science in Business Analytics', dept:'Business, Economics & Management', campus:'Kigali Heights Campus', years:3},
      {name:'Arts in Communications', dept:'Arts, Humanities & Communication', campus:'Kigali Heights Campus', years:3},
    ],
    vals:{} },
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
