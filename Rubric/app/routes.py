from flask import render_template, redirect, url_for, flash, request, current_app as app, send_from_directory
from app import db
from app.models import User, Audio, Payment, Faculty, Course, Purchase
from flask_login import current_user, login_user, logout_user, login_required
from app.forms import LoginForm, RegistrationForm, ProfileForm
from werkzeug.utils import secure_filename
import os

# Home page route
@app.route('/')
@app.route('/index')
def index():
    levels = [100, 200, 300, 400]
    return render_template('index.html', title='Home', levels=levels)

# Login route
@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(email=form.email.data).first()
        if user is None or not user.check_password(form.password.data):
            flash('Invalid username or password', 'danger')
            return redirect(url_for('login'))
        login_user(user, remember=form.remember.data)
        return redirect(url_for('index'))
    return render_template('login.html', title='Sign In', form=form)

# Logout route
@app.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('index'))

# Signup route
@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = RegistrationForm()
    if form.validate_on_submit():
        user = User(username=form.username.data, email=form.email.data)
        user.set_password(form.password.data)
        db.session.add(user)
        db.session.commit()
        flash('Congratulations, you are now a registered user!', 'success')
        return redirect(url_for('login'))
    return render_template('signup.html', title='Register', form=form)

# Profile route
@app.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    form = ProfileForm()
    if form.validate_on_submit():
        current_user.username = form.username.data
        current_user.email = form.email.data
        current_user.bio = form.bio.data
        if form.profile_picture.data:
            filename = secure_filename(form.profile_picture.data.filename)
            file_path = os.path.join(current_app.config['UPLOAD_FOLDER'], filename)
            form.profile_picture.data.save(file_path)
            current_user.profile_image = filename
            flash(f'Profile picture saved as {filename}', 'success')
        db.session.commit()
        flash('Your changes have been saved.', 'success')
        return redirect(url_for('profile'))
    elif request.method == 'GET':
        form.username.data = current_user.username
        form.email.data = current_user.email
        form.bio.data = current_user.bio
    return render_template('profile.html', title='Profile', form=form)

# Levels route
@app.route('/levels/<int:level>')
@login_required
def levels(level):
    faculties = Faculty.query.all()
    return render_template('levels.html', title=f'{level} Level', level=level, faculties=faculties)

@app.route('/levels/<int:level>/faculty/<int:faculty_id>')
@login_required
def faculty(level, faculty_id):
    faculty = Faculty.query.get_or_404(faculty_id)
    courses = Course.query.filter_by(faculty_id=faculty_id).all()
    current_app.logger.debug(f"Faculty: {faculty}, Courses: {courses}")
    return render_template('faculty.html', title=f'{faculty.name} Faculty', level=level, faculty=faculty, courses=courses)


@app.route('/levels/<int:level>/faculty/<int:faculty_id>/courses/<int:course_id>')
@login_required
def courses(level, faculty_id, course_id):
    course = Course.query.get_or_404(course_id)
    current_app.logger.debug(f"Course: {course}")
    audios = Audio.query.filter_by(course_id=course.id).all()
    return render_template('courses.html', title=course.course_name, level=level, faculty_id=faculty_id, course=course, audios=audios)

# Admin route
@app.route('/admin')
@login_required
def admin():
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('index'))
    
    audios = Audio.query.all()
    purchases = Purchase.query.all()
    total_amount = sum(purchase.amount for purchase in Payment.query.all())
    total_purchases = len(purchases)
    return render_template('admin.html', audios=audios, purchases=purchases, total_amount=total_amount, total_purchases=total_purchases)

# Upload audio route
@app.route('/admin/upload', methods=['GET', 'POST'])
@login_required
def upload_audio():
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('admin'))
    
    if request.method == 'POST':
        title = request.form['title']
        price = request.form['price']
        course_id = request.form['course_id']
        file = request.files['file']
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file.save(os.path.join(current_app.config['UPLOAD_FOLDER'], filename))
            audio = Audio(title=title, filename=filename, price=price, course_id=course_id)
            db.session.add(audio)
            db.session.commit()
            flash('Audio uploaded successfully!', 'success')
            return redirect(url_for('admin'))
        else:
            flash('Invalid file format.', 'danger')
    courses = Course.query.all()
    return render_template('upload_audio.html', courses=courses)

@app.route('/purchase/<int:audio_id>', methods=['GET', 'POST'])
@login_required
def purchase_audio(audio_id):
    audio = Audio.query.get_or_404(audio_id)
    if request.method == 'POST':
        payment = Payment(user_id=current_user.id, amount=audio.price)
        db.session.add(payment)
        db.session.commit()
        purchase = Purchase(user_id=current_user.id, audio_id=audio.id, amount=audio.price)
        db.session.add(purchase)
        db.session.commit()
        flash('Purchase successful!', 'success')
        return redirect(url_for('download_audio', audio_id=audio.id))
    return render_template('purchase_audio.html', audio=audio)

# Download audio route
@app.route('/download/<int:audio_id>')
@login_required
def download_audio(audio_id):
    audio = Audio.query.get_or_404(audio_id)
    payment = Payment.query.filter_by(user_id=current_user.id, audio_id=audio_id).first()
    if not payment:
        flash('You need to pay before downloading this audio.', 'danger')
        return redirect(url_for('courses', level=audio.course.level, faculty_id=audio.course.faculty_id, course_id=audio.course_id))
    return send_from_directory(current_app.config['UPLOAD_FOLDER'], audio.filename, as_attachment=True)
# Route to select level
@app.route('/admin/levels')
@login_required
def admin_levels():
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('index'))
    
    levels = [100, 200, 300, 400]
    return render_template('admin_levels.html', levels=levels)

# Route to select faculty based on level
@app.route('/admin/levels/<int:level>/faculties')
@login_required
def admin_faculties(level):
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('index'))
    
    faculties = Faculty.query.all()
    return render_template('admin_faculties.html', level=level, faculties=faculties)

# Route to select course based on faculty and level
@app.route('/admin/levels/<int:level>/faculties/<int:faculty_id>/courses')
@login_required
def admin_courses(level, faculty_id):
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('index'))
    
    courses = Course.query.filter_by(faculty_id=faculty_id).all()
    return render_template('admin_courses.html', level=level, faculty_id=faculty_id, courses=courses)

# Route to upload audio file based on course, faculty, and level
@app.route('/admin/levels/<int:level>/faculties/<int:faculty_id>/courses/<int:course_id>/upload', methods=['GET', 'POST'])
@login_required
def admin_upload_audio(level, faculty_id, course_id):
    if not current_user.is_admin:
        flash('You do not have access to this page.', 'danger')
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        title = request.form['title']
        price = request.form['price']
        file = request.files['file']
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file.save(os.path.join(current_app.config['UPLOAD_FOLDER'], filename))
            audio = Audio(title=title, filename=filename, price=price, course_id=course_id)
            db.session.add(audio)
            db.session.commit()
            flash('Audio uploaded successfully!', 'success')
            return redirect(url_for('admin_courses', level=level, faculty_id=faculty_id))
        else:
            flash('Invalid file format.', 'danger')
    
    return render_template('admin_upload_audio.html', level=level, faculty_id=faculty_id, course_id=course_id)

# Helper function to check allowed file extensions
def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in current_app.config['ALLOWED_EXTENSIONS']