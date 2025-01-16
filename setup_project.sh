#!/bin/bash

# Project name
PROJECT_NAME="Rubric"

# Create project directories
mkdir -p $PROJECT_NAME/{app/{templates,static/{css,js,images,uploads}},migrations}

# Create __init__.py for the app
cat <<EOF > $PROJECT_NAME/app/__init__.py
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

app = Flask(__name__)
app.config.from_object('config.Config')

db = SQLAlchemy(app)
migrate = Migrate(app, db)
login = LoginManager(app)
limiter = Limiter(app, key_func=get_remote_address)

from app import routes, models
EOF

# Create config.py
cat <<EOF > $PROJECT_NAME/config.py
import os

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'your_secret_key')
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', 'mysql+pymysql://username:password@localhost/db_name')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_FOLDER = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'app/static/uploads')
    STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY')
EOF

# Create models.py
cat <<EOF > $PROJECT_NAME/app/models.py
from app import db
from flask_login import UserMixin
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), index=True, unique=True)
    email = db.Column(db.String(120), index=True, unique=True)
    password_hash = db.Column(db.String(128))
    profile_picture = db.Column(db.String(120), default='default.jpg')
    bio = db.Column(db.String(256))
    registered_on = db.Column(db.DateTime, default=datetime.utcnow)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def __repr__(self):
        return f'<User {self.username}>'

class Audio(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(128))
    file_path = db.Column(db.String(256))
    uploaded_on = db.Column(db.DateTime, default=datetime.utcnow)
    price = db.Column(db.Float)

    def __repr__(self):
        return f'<Audio {self.title}>'

class Payment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    audio_id = db.Column(db.Integer, db.ForeignKey('audio.id'))
    amount = db.Column(db.Float)
    paid_on = db.Column(db.DateTime, default=datetime.utcnow)

    def __repr__(self):
        return f'<Payment {self.amount}>'
EOF

# Create routes.py
cat <<EOF > $PROJECT_NAME/app/routes.py
from flask import render_template, redirect, url_for, flash, request
from app import app, db, login
from app.models import User, Audio, Payment
from flask_login import current_user, login_user, logout_user, login_required
from app.forms import LoginForm, SignupForm, ProfileForm
from werkzeug.utils import secure_filename
import os

@app.route('/')
@app.route('/index')
def index():
    audios = Audio.query.all()
    return render_template('index.html', title='Home', audios=audios)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(email=form.email.data).first()
        if user is None or not user.check_password(form.password.data):
            flash('Invalid username or password')
            return redirect(url_for('login'))
        login_user(user, remember=form.remember_me.data)
        return redirect(url_for('index'))
    return render_template('login.html', title='Sign In', form=form)

@app.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('index'))

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = SignupForm()
    if form.validate_on_submit():
        user = User(username=form.username.data, email=form.email.data)
        user.set_password(form.password.data)
        db.session.add(user)
        db.session.commit()
        flash('Congratulations, you are now a registered user!')
        return redirect(url_for('login'))
    return render_template('signup.html', title='Register', form=form)

@app.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    form = ProfileForm()
    if form.validate_on_submit():
        current_user.username = form.username.data
        current_user.bio = form.bio.data
        if form.profile_picture.data:
            filename = secure_filename(form.profile_picture.data.filename)
            form.profile_picture.data.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
            current_user.profile_picture = filename
        db.session.commit()
        flash('Your changes have been saved.')
        return redirect(url_for('profile'))
    elif request.method == 'GET':
        form.username.data = current_user.username
        form.bio.data = current_user.bio
    return render_template('profile.html', title='Profile', form=form)

@app.route('/upload_audio', methods=['GET', 'POST'])
@login_required
def upload_audio():
    if not current_user.is_admin:
        flash('You do not have access to this page.')
        return redirect(url_for('index'))
    if request.method == 'POST':
        title = request.form['title']
        price = request.form['price']
        file = request.files['file']
        filename = secure_filename(file.filename)
        file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        audio = Audio(title=title, file_path=filename, price=price)
        db.session.add(audio)
        db.session.commit()
        flash('Audio uploaded successfully!')
        return redirect(url_for('index'))
    return render_template('upload_audio.html', title='Upload Audio')

@app.route('/download/<int:audio_id>')
@login_required
def download_audio(audio_id):
    audio = Audio.query.get_or_404(audio_id)
    payment = Payment.query.filter_by(user_id=current_user.id, audio_id=audio_id).first()
    if not payment:
        flash('You need to pay before downloading this audio.')
        return redirect(url_for('index'))
    return redirect(url_for('static', filename=f'uploads/{audio.file_path}'))
EOF

# Create forms.py
cat <<EOF > $PROJECT_NAME/app/forms.py
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField, TextAreaField
from wtforms.validators import DataRequired, ValidationError, Email, EqualTo
from flask_wtf.file import FileField, FileAllowed
from app.models import User

class LoginForm(FlaskForm):
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    remember_me = BooleanField('Remember Me')
    submit = SubmitField('Sign In')

class SignupForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    password2 = PasswordField('Repeat Password', validators=[DataRequired(), EqualTo('password')])
    submit = SubmitField('Register')

    def validate_username(self, username):
        user = User.query.filter_by(username=username.data).first()
        if user is not None:
            raise ValidationError('Please use a different username.')

    def validate_email(self, email):
        user = User.query.filter_by(email=email.data).first()
        if user is not None:
            raise ValidationError('Please use a different email address.')

class ProfileForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    bio = TextAreaField('Bio', validators=[DataRequired()])
    profile_picture = FileField('Profile Picture', validators=[FileAllowed(['jpg', 'png'])])
    submit = SubmitField('Save Changes')
EOF

# Create base.html
cat <<EOF > $PROJECT_NAME/app/templates/base.html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>{{ title }} - Rubric</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/styles.css') }}">
  </head>
  <body>
    <nav>
      <a href="{{ url_for('index') }}">Home</a>
      {% if current_user.is_authenticated %}
        <a href="{{ url_for('profile') }}">Profile</a>
        <a href="{{ url_for('logout') }}">Logout</a>
      {% else %}
        <a href="{{ url_for('login') }}">Login</a>
        <a href="{{ url_for('signup') }}">Signup</a>
      {% endif %}
    </nav>
    <div class="container">
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          {% for category, message in messages %}
            <div class="alert alert-{{ category }}">{{ message }}</div>
          {% endfor %}
        {% endif %}
      {% endwith %}
      {% block content %}{% endblock %}
    </div>
  </body>
</html>
EOF

# Create index.html
cat <<EOF > $PROJECT_NAME/app/templates/index.html
{% extends "base.html" %}
{% block content %}
  <h1>Welcome to Rubric</h1>
  <ul>
    {% for audio in audios %}
      <li>{{ audio.title }} - \${{ audio.price }}</li>
    {% endfor %}
  </ul>
{% endblock %}
EOF

# Create login.html
cat <<EOF > $PROJECT_NAME/app/templates/login.html
{% extends "base.html" %}
{% block content %}
  <h1>Sign In</h1>
  <form method="POST" action="{{ url_for('login') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.email.label }}<br>
      {{ form.email(size=32) }}
    </p>
    <p>
      {{ form.password.label }}<br>
      {{ form.password(size=32) }}
    </p>
    <p>{{ form.remember_me() }} {{ form.remember_me.label }}</p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create signup.html
cat <<EOF > $PROJECT_NAME/app/templates/signup.html
{% extends "base.html" %}
{% block content %}
  <h1>Register</h1>
  <form method="POST" action="{{ url_for('signup') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.username.label }}<br>
      {{ form.username(size=32) }}
    </p>
    <p>
      {{ form.email.label }}<br>
      {{ form.email(size=32) }}
    </p>
    <p>
      {{ form.password.label }}<br>
      {{ form.password(size=32) }}
    </p>
    <p>
      {{ form.password2.label }}<br>
      {{ form.password2(size=32) }}
    </p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create profile.html
cat <<EOF > $PROJECT_NAME/app/templates/profile.html
{% extends "base.html" %}
{% block content %}
  <h1>Profile</h1>
  <form method="POST" enctype="multipart/form-data" action="{{ url_for('profile') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.username.label }}<br>
      {{ form.username(size=32) }}
    </p>
    <p>
      {{ form.bio.label }}<br>
      {{ form.bio(rows=4, cols=32) }}
    </p>
    <p>
      {{ form.profile_picture.label }}<br>
      {{ form.profile_picture() }}
    </p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create upload_audio.html
cat <<EOF > $PROJECT_NAME/app/templates/upload_audio.html
{% extends "base.html" %}
{% block content %}
  <h1>Upload Audio</h1>
  <form method="POST" enctype="multipart/form-data" action="{{ url_for('upload_audio') }}">
    <p>
      <label for="title">Title</label><br>
      <input type="text" name="title" id="title" size="32">
    </p>
    <p>
      <label for="price">Price</label><br>
      <input type="text" name="price" id="price" size="32">
    </p>
    <p>
      <label for="file">File</label><br>
      <input type="file" name="file" id="file">
    </p>
    <p><input type="submit" value="Upload"></p>
  </form>
{% endblock %}
EOF

# Create run.py
cat <<EOF > $PROJECT_NAME/run.py
from app import app

if __name__ == "__main__":
    app.run(debug=True)
EOF

# Create README.md
cat <<EOF > $PROJECT_NAME/README.md
# Rubric

Rubric is a web application built with Flask to manage user authentication and audio file uploads.

## Setup

1. Create a virtual environment and activate it:
    ```sh
    python3 -m venv venv
    source venv/bin/activate
    ```

2. Install the required packages:
    ```sh
    pip install -r requirements.txt
    ```

3. Set up the database:
    ```sh
    flask db init
    flask db migrate -m "Initial migration."
    flask db upgrade
    ```

4. Run the application:
    ```sh
    python run.py
    ```

## Configuration

Update the `config.py` file with your own configuration settings, such as the database URI and secret key.
EOF

# Create requirements.txt
cat <<EOF > $PROJECT_NAME/requirements.txt
Flask
Flask-SQLAlchemy
Flask-Migrate
Flask-Login
Flask-WTF
Flask-Uploads
Flask-Limiter
stripe
EOF

echo "Project setup complete. Navigate to the $PROJECT_NAME directory and follow the README instructions to get started."#!/bin/bash

# Project name
PROJECT_NAME="Rubric"

# Create project directories
mkdir -p $PROJECT_NAME/{app/{templates,static/{css,js,images,uploads}},migrations}

# Create __init__.py for the app
cat <<EOF > $PROJECT_NAME/app/__init__.py
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

app = Flask(__name__)
app.config.from_object('config.Config')

db = SQLAlchemy(app)
migrate = Migrate(app, db)
login = LoginManager(app)
limiter = Limiter(app, key_func=get_remote_address)

from app import routes, models
EOF

# Create config.py
cat <<EOF > $PROJECT_NAME/config.py
import os

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'your_secret_key')
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', 'mysql+pymysql://username:password@localhost/db_name')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_FOLDER = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'app/static/uploads')
    STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY')
EOF

# Create models.py
cat <<EOF > $PROJECT_NAME/app/models.py
from app import db
from flask_login import UserMixin
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), index=True, unique=True)
    email = db.Column(db.String(120), index=True, unique=True)
    password_hash = db.Column(db.String(128))
    profile_picture = db.Column(db.String(120), default='default.jpg')
    bio = db.Column(db.String(256))
    registered_on = db.Column(db.DateTime, default=datetime.utcnow)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def __repr__(self):
        return f'<User {self.username}>'

class Audio(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(128))
    file_path = db.Column(db.String(256))
    uploaded_on = db.Column(db.DateTime, default=datetime.utcnow)
    price = db.Column(db.Float)

    def __repr__(self):
        return f'<Audio {self.title}>'

class Payment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    audio_id = db.Column(db.Integer, db.ForeignKey('audio.id'))
    amount = db.Column(db.Float)
    paid_on = db.Column(db.DateTime, default=datetime.utcnow)

    def __repr__(self):
        return f'<Payment {self.amount}>'
EOF

# Create routes.py
cat <<EOF > $PROJECT_NAME/app/routes.py
from flask import render_template, redirect, url_for, flash, request
from app import app, db, login
from app.models import User, Audio, Payment
from flask_login import current_user, login_user, logout_user, login_required
from app.forms import LoginForm, SignupForm, ProfileForm
from werkzeug.utils import secure_filename
import os

@app.route('/')
@app.route('/index')
def index():
    audios = Audio.query.all()
    return render_template('index.html', title='Home', audios=audios)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(email=form.email.data).first()
        if user is None or not user.check_password(form.password.data):
            flash('Invalid username or password')
            return redirect(url_for('login'))
        login_user(user, remember=form.remember_me.data)
        return redirect(url_for('index'))
    return render_template('login.html', title='Sign In', form=form)

@app.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('index'))

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    form = SignupForm()
    if form.validate_on_submit():
        user = User(username=form.username.data, email=form.email.data)
        user.set_password(form.password.data)
        db.session.add(user)
        db.session.commit()
        flash('Congratulations, you are now a registered user!')
        return redirect(url_for('login'))
    return render_template('signup.html', title='Register', form=form)

@app.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    form = ProfileForm()
    if form.validate_on_submit():
        current_user.username = form.username.data
        current_user.bio = form.bio.data
        if form.profile_picture.data:
            filename = secure_filename(form.profile_picture.data.filename)
            form.profile_picture.data.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
            current_user.profile_picture = filename
        db.session.commit()
        flash('Your changes have been saved.')
        return redirect(url_for('profile'))
    elif request.method == 'GET':
        form.username.data = current_user.username
        form.bio.data = current_user.bio
    return render_template('profile.html', title='Profile', form=form)

@app.route('/upload_audio', methods=['GET', 'POST'])
@login_required
def upload_audio():
    if not current_user.is_admin:
        flash('You do not have access to this page.')
        return redirect(url_for('index'))
    if request.method == 'POST':
        title = request.form['title']
        price = request.form['price']
        file = request.files['file']
        filename = secure_filename(file.filename)
        file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        audio = Audio(title=title, file_path=filename, price=price)
        db.session.add(audio)
        db.session.commit()
        flash('Audio uploaded successfully!')
        return redirect(url_for('index'))
    return render_template('upload_audio.html', title='Upload Audio')

@app.route('/download/<int:audio_id>')
@login_required
def download_audio(audio_id):
    audio = Audio.query.get_or_404(audio_id)
    payment = Payment.query.filter_by(user_id=current_user.id, audio_id=audio_id).first()
    if not payment:
        flash('You need to pay before downloading this audio.')
        return redirect(url_for('index'))
    return redirect(url_for('static', filename=f'uploads/{audio.file_path}'))
EOF

# Create forms.py
cat <<EOF > $PROJECT_NAME/app/forms.py
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField, TextAreaField
from wtforms.validators import DataRequired, ValidationError, Email, EqualTo
from flask_wtf.file import FileField, FileAllowed
from app.models import User

class LoginForm(FlaskForm):
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    remember_me = BooleanField('Remember Me')
    submit = SubmitField('Sign In')

class SignupForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    password2 = PasswordField('Repeat Password', validators=[DataRequired(), EqualTo('password')])
    submit = SubmitField('Register')

    def validate_username(self, username):
        user = User.query.filter_by(username=username.data).first()
        if user is not None:
            raise ValidationError('Please use a different username.')

    def validate_email(self, email):
        user = User.query.filter_by(email=email.data).first()
        if user is not None:
            raise ValidationError('Please use a different email address.')

class ProfileForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    bio = TextAreaField('Bio', validators=[DataRequired()])
    profile_picture = FileField('Profile Picture', validators=[FileAllowed(['jpg', 'png'])])
    submit = SubmitField('Save Changes')
EOF

# Create base.html
cat <<EOF > $PROJECT_NAME/app/templates/base.html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>{{ title }} - Rubric</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/styles.css') }}">
  </head>
  <body>
    <nav>
      <a href="{{ url_for('index') }}">Home</a>
      {% if current_user.is_authenticated %}
        <a href="{{ url_for('profile') }}">Profile</a>
        <a href="{{ url_for('logout') }}">Logout</a>
      {% else %}
        <a href="{{ url_for('login') }}">Login</a>
        <a href="{{ url_for('signup') }}">Signup</a>
      {% endif %}
    </nav>
    <div class="container">
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          {% for category, message in messages %}
            <div class="alert alert-{{ category }}">{{ message }}</div>
          {% endfor %}
        {% endif %}
      {% endwith %}
      {% block content %}{% endblock %}
    </div>
  </body>
</html>
EOF

# Create index.html
cat <<EOF > $PROJECT_NAME/app/templates/index.html
{% extends "base.html" %}
{% block content %}
  <h1>Welcome to Rubric</h1>
  <ul>
    {% for audio in audios %}
      <li>{{ audio.title }} - \${{ audio.price }}</li>
    {% endfor %}
  </ul>
{% endblock %}
EOF

# Create login.html
cat <<EOF > $PROJECT_NAME/app/templates/login.html
{% extends "base.html" %}
{% block content %}
  <h1>Sign In</h1>
  <form method="POST" action="{{ url_for('login') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.email.label }}<br>
      {{ form.email(size=32) }}
    </p>
    <p>
      {{ form.password.label }}<br>
      {{ form.password(size=32) }}
    </p>
    <p>{{ form.remember_me() }} {{ form.remember_me.label }}</p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create signup.html
cat <<EOF > $PROJECT_NAME/app/templates/signup.html
{% extends "base.html" %}
{% block content %}
  <h1>Register</h1>
  <form method="POST" action="{{ url_for('signup') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.username.label }}<br>
      {{ form.username(size=32) }}
    </p>
    <p>
      {{ form.email.label }}<br>
      {{ form.email(size=32) }}
    </p>
    <p>
      {{ form.password.label }}<br>
      {{ form.password(size=32) }}
    </p>
    <p>
      {{ form.password2.label }}<br>
      {{ form.password2(size=32) }}
    </p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create profile.html
cat <<EOF > $PROJECT_NAME/app/templates/profile.html
{% extends "base.html" %}
{% block content %}
  <h1>Profile</h1>
  <form method="POST" enctype="multipart/form-data" action="{{ url_for('profile') }}">
    {{ form.hidden_tag() }}
    <p>
      {{ form.username.label }}<br>
      {{ form.username(size=32) }}
    </p>
    <p>
      {{ form.bio.label }}<br>
      {{ form.bio(rows=4, cols=32) }}
    </p>
    <p>
      {{ form.profile_picture.label }}<br>
      {{ form.profile_picture() }}
    </p>
    <p>{{ form.submit() }}</p>
  </form>
{% endblock %}
EOF

# Create upload_audio.html
cat <<EOF > $PROJECT_NAME/app/templates/upload_audio.html
{% extends "base.html" %}
{% block content %}
  <h1>Upload Audio</h1>
  <form method="POST" enctype="multipart/form-data" action="{{ url_for('upload_audio') }}">
    <p>
      <label for="title">Title</label><br>
      <input type="text" name="title" id="title" size="32">
    </p>
    <p>
      <label for="price">Price</label><br>
      <input type="text" name="price" id="price" size="32">
    </p>
    <p>
      <label for="file">File</label><br>
      <input type="file" name="file" id="file">
    </p>
    <p><input type="submit" value="Upload"></p>
  </form>
{% endblock %}
EOF

# Create run.py
cat <<EOF > $PROJECT_NAME/run.py
from app import app

if __name__ == "__main__":
    app.run(debug=True)
EOF

# Create README.md
cat <<EOF > $PROJECT_NAME/README.md
# Rubric

Rubric is a web application built with Flask to manage user authentication and audio file uploads.

## Setup

1. Create a virtual environment and activate it:
    ```sh
    python3 -m venv venv
    source venv/bin/activate
    ```

2. Install the required packages:
    ```sh
    pip install -r requirements.txt
    ```

3. Set up the database:
    ```sh
    flask db init
    flask db migrate -m "Initial migration."
    flask db upgrade
    ```

4. Run the application:
    ```sh
    python run.py
    ```

## Configuration

Update the `config.py` file with your own configuration settings, such as the database URI and secret key.
EOF

# Create requirements.txt
cat <<EOF > $PROJECT_NAME/requirements.txt
Flask
Flask-SQLAlchemy
Flask-Migrate
Flask-Login
Flask-WTF
Flask-Uploads
Flask-Limiter
stripe
EOF

echo "Project setup complete. Navigate to the $PROJECT_NAME directory and follow the README instructions to get started."