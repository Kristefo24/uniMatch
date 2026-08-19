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
  'Computer Science', 'Software Engineering', 'Information Technology',
  'Business Administration', 'Accounting', 'Nursing', 'Medicine', 'Pharmacy',
];

// Each university: vals carry the criteria the ranking reads.
const UNIVERSITIES = [
  { id:'uni-uok', abbr:'UoK', name:'University of Kigali',
    campuses:[
      {name:'Remera Campus', depts:['School of Business Management & Economics']},
      {name:'Main Campus', depts:['School of Computing and Information Technology','School of Education','School of Law']},
    ],
    programmes:[
      {name:'Public Administration and Local Governance', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Marketing (Hons)', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Supplies and Procurement Management (Hons)', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Economics (Hons)', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Finance (Hons)', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Accounting (Hons)', dept:'School of Business Management & Economics', campus:'Remera Campus', years:4},
      {name:'Information Technology (Hons)', dept:'School of Computing and Information Technology', campus:'Main Campus', years:4},
      {name:'Computer Science (Hons)', dept:'School of Computing and Information Technology', campus:'Main Campus', years:4},
      {name:'Business Information Technology (Hons)', dept:'School of Computing and Information Technology', campus:'Main Campus', years:4},
      {name:'Early Childhood Development Education (ECD)', dept:'School of Education', campus:'Main Campus', years:4},
      {name:'Law (Hons)', dept:'School of Law', campus:'Main Campus', years:4},
    ],
    vals:{} },

  { id:'uni-eau', abbr:'EAU', name:'East African University',
    campuses:[{name:'Kicukiro Campus', depts:['Film making & Film Production','Leisure, Tourism & Hotel Management','Mass Communication & Journalism']}],
    programmes:[
      {name:'Theatre & Performing Arts', dept:'Film making & Film Production', campus:'Kicukiro Campus', years:3},
      {name:'Animation & Visual Effects', dept:'Film making & Film Production', campus:'Kicukiro Campus', years:3},
      {name:'Media & Communication', dept:'Film making & Film Production', campus:'Kicukiro Campus', years:3},
      {name:'Film Editing & Post-Production', dept:'Film making & Film Production', campus:'Kicukiro Campus', years:3},
      {name:'Tourism Management', dept:'Leisure, Tourism & Hotel Management', campus:'Kicukiro Campus', years:3},
      {name:'Hotel & Hospitality Management', dept:'Leisure, Tourism & Hotel Management', campus:'Kicukiro Campus', years:3},
      {name:'Leisure Management', dept:'Leisure, Tourism & Hotel Management', campus:'Kicukiro Campus', years:3},
      {name:'Travel & Tourism', dept:'Leisure, Tourism & Hotel Management', campus:'Kicukiro Campus', years:3},
      {name:'Journalism', dept:'Mass Communication & Journalism', campus:'Kicukiro Campus', years:3},
      {name:'Journalism Radio & Television Broadcasting', dept:'Mass Communication & Journalism', campus:'Kicukiro Campus', years:3},
      {name:'Public Relations', dept:'Mass Communication & Journalism', campus:'Kicukiro Campus', years:3},
    ],
    vals:{} },

  { id:'uni-alu', abbr:'ALU', name:'African Leadership University',
    campuses:[{name:'Bumbogo Campus', depts:['Entrepreneurship & Leadership','Computing & IT','School of Business and Management']}],
    programmes:[
      {name:'Entrepreneurial Leadership (BEL)', dept:'Entrepreneurship & Leadership', campus:'Bumbogo Campus', years:3},
      {name:'Software Engineering (BSE)', dept:'Computing & IT', campus:'Bumbogo Campus', years:3},
      {name:'Information Technology', dept:'Computing & IT', campus:'Bumbogo Campus', years:3},
      {name:'Business Information and Technology', dept:'Computing & IT', campus:'Bumbogo Campus', years:3},
      {name:'International Business & Trade (IBT)', dept:'School of Business and Management', campus:'Bumbogo Campus', years:3},
      {name:'Strategic Management', dept:'School of Business and Management', campus:'Bumbogo Campus', years:3},
    ],
    vals:{} },

  { id:'uni-auca', abbr:'AUCA', name:'Adventist University of Central Africa',
    campuses:[
      {name:'Gishushu Campus', depts:['Faculty of Information Technology']},
      {name:'Masoro Campus', depts:['Department of Business Administration','Department of Education','Faculty of Theology','Nursing and Midwifery']},
    ],
    programmes:[
      {name:'Software Engineering', dept:'Faculty of Information Technology', campus:'Gishushu Campus', years:4},
      {name:'Information Management', dept:'Faculty of Information Technology', campus:'Gishushu Campus', years:4},
      {name:'Network & Communication Systems', dept:'Faculty of Information Technology', campus:'Gishushu Campus', years:4},
      {name:'Marketing', dept:'Department of Business Administration', campus:'Masoro Campus', years:4},
      {name:'Management', dept:'Department of Business Administration', campus:'Masoro Campus', years:4},
      {name:'Finance', dept:'Department of Business Administration', campus:'Masoro Campus', years:4},
      {name:'Accounting', dept:'Department of Business Administration', campus:'Masoro Campus', years:4},
      {name:'Education Psychology', dept:'Department of Education', campus:'Masoro Campus', years:4},
      {name:'Literature & Languages', dept:'Department of Education', campus:'Masoro Campus', years:4},
      {name:'Mathematics & Sciences', dept:'Department of Education', campus:'Masoro Campus', years:4},
      {name:'Theology', dept:'Faculty of Theology', campus:'Masoro Campus', years:3},
      {name:'Nursing and Midwifery', dept:'Nursing and Midwifery', campus:'Masoro Campus', years:5},
    ],
    vals:{} },

  { id:'uni-urcmhs', abbr:'UR/CMHS', name:'UR College of Medicine & Health Sciences',
    campuses:[{name:'Remera Campus', depts:['School of Medicine & Pharmacy','School of Nursing & Midwifery','School of Public Health','School of Dentistry','School of Health Sciences']}],
    programmes:[
      {name:'Medicine', dept:'School of Medicine & Pharmacy', campus:'Remera Campus', years:5},
      {name:'Pharmacy', dept:'School of Medicine & Pharmacy', campus:'Remera Campus', years:5},
      {name:'Nursing', dept:'School of Nursing & Midwifery', campus:'Remera Campus', years:5},
      {name:'Midwifery', dept:'School of Nursing & Midwifery', campus:'Remera Campus', years:5},
      {name:'Public Health', dept:'School of Public Health', campus:'Remera Campus', years:5},
      {name:'Health Promotion', dept:'School of Public Health', campus:'Remera Campus', years:5},
      {name:'Dentist', dept:'School of Dentistry', campus:'Remera Campus', years:5},
      {name:'Dental Surgery', dept:'School of Dentistry', campus:'Remera Campus', years:5},
      {name:'Medical Laboratory Science', dept:'School of Health Sciences', campus:'Remera Campus', years:5},
      {name:'Radiography', dept:'School of Health Sciences', campus:'Remera Campus', years:5},
      {name:'Nutrition', dept:'School of Health Sciences', campus:'Remera Campus', years:5},
    ],
    vals:{} },

  { id:'uni-ulk', abbr:'ULK', name:'Kigali Independent University',
    campuses:[{name:'Gisozi Campus', depts:['School of Economics & Business Studies','School of Social Sciences','School of Law','School of Science & Technology']}],
    programmes:[
      {name:'Economics (Hons)', dept:'School of Economics & Business Studies', campus:'Gisozi Campus', years:4},
      {name:'Finance (Hons)', dept:'School of Economics & Business Studies', campus:'Gisozi Campus', years:4},
      {name:'Accounting (Hons)', dept:'School of Economics & Business Studies', campus:'Gisozi Campus', years:4},
      {name:'Rural Development (Hons)', dept:'School of Economics & Business Studies', campus:'Gisozi Campus', years:4},
      {name:'Management (Hons)', dept:'School of Economics & Business Studies', campus:'Gisozi Campus', years:4},
      {name:'Development Studies (Hons)', dept:'School of Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'International Relations (Hons)', dept:'School of Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Population Studies (Hons)', dept:'School of Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Sociology (Hons)', dept:'School of Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Administrative Sciences (Hons)', dept:'School of Social Sciences', campus:'Gisozi Campus', years:4},
      {name:'Administrative Sciences (Hons)', dept:'School of Law', campus:'Gisozi Campus', years:4},
      {name:'Private Law (Hons)', dept:'School of Law', campus:'Gisozi Campus', years:4},
      {name:'Data Science (Hons)', dept:'School of Science & Technology', campus:'Gisozi Campus', years:4},
      {name:'Software Engineering (Hons)', dept:'School of Science & Technology', campus:'Gisozi Campus', years:4},
      {name:'Networking (Hons)', dept:'School of Science & Technology', campus:'Gisozi Campus', years:4},
    ],
    vals:{} },

  { id:'uni-kepler', abbr:'Kepler', name:'Kepler College',
    campuses:[{name:'Kigali Heights Campus', depts:['Project Management','Business Analytics','Media and Communication']}],
    programmes:[
      {name:'Arts in Project Management', dept:'Project Management', campus:'Kigali Heights Campus', years:3},
      {name:'Science in Business Analytics', dept:'Business Analytics', campus:'Kigali Heights Campus', years:3},
      {name:'Arts in Communications', dept:'Media and Communication', campus:'Kigali Heights Campus', years:3},
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
  };
}

module.exports = { DEFAULT_ADMIN, DEPARTMENTS, UNIVERSITIES, STAFF_REQUESTS, CRITERIA, STUDENTS, freshStore, buildProgrammes };
