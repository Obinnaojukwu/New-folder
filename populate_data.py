from app import app, db
from app.models import Faculty, Course

# Define faculties and courses
faculties = [
    'Faculty of Agriculture',
    'Faculty of Arts',
    'Faculty of Education',
    'Faculty of Engineering',
    'Faculty of Law',
    'Faculty of Life Sciences',
    'Faculty of Management Sciences',
    'Faculty of Pharmacy',
    'Faculty of Physical Sciences',
    'Faculty of Social Sciences',
    'College of Medical Sciences',
    'Faculty of Environmental Sciences'
]

courses = {
    'Faculty of Agriculture': [
        'Agricultural Economics', 'Agricultural Extension', 'Animal Science', 'Crop Science', 'Food Science', 'Forestry', 'Soil Science'
    ],
    'Faculty of Arts': [
        'English Language & Literature', 'Fine & Applied Arts', 'French', 'History', 'Linguistics', 'Philosophy', 'Religious Studies', 'Theatre Arts'
    ],
    'Faculty of Education': [
        'Adult Education', 'Education', 'Educational Management', 'Guidance & Counseling', 'Library Science', 'Physical Education', 'Primary Education', 'Special Education'
    ],
    'Faculty of Engineering': [
        'Agricultural Engineering', 'Chemical Engineering', 'Civil Engineering', 'Computer Engineering', 'Electrical/Electronic Engineering', 'Mechanical Engineering', 'Petroleum Engineering'
    ],
    'Faculty of Law': ['Law'],
    'Faculty of Life Sciences': ['Biochemistry', 'Botany', 'Microbiology', 'Zoology'],
    'Faculty of Management Sciences': ['Accounting', 'Banking & Finance', 'Business Administration', 'Marketing', 'Public Administration'],
    'Faculty of Pharmacy': ['Pharmacy', 'Pharmacology'],
    'Faculty of Physical Sciences': ['Chemistry', 'Computer Science', 'Geology', 'Mathematics', 'Physics'],
    'Faculty of Social Sciences': ['Economics', 'Geography', 'Mass Communication', 'Sociology', 'Statistics'],
    'College of Medical Sciences': ['Anatomy', 'Biochemistry', 'Medicine', 'Nursing', 'Optometry', 'Physiology', 'Pharmacy'],
    'Faculty of Environmental Sciences': ['Architecture', 'Building', 'Estate Management', 'Environmental Science', 'Quantity Surveying', 'Urban and Regional Planning']
}

with app.app_context():
    for faculty_name in faculties:
        faculty = Faculty(name=faculty_name, department=faculty_name)  # Ensure the department field is populated
        db.session.add(faculty)
        db.session.commit()
        for course_name in courses[faculty_name]:
            course = Course(course_name=course_name, faculty_id=faculty.id)
            db.session.add(course)
        db.session.commit()

print("Database has been populated with faculties and courses.")