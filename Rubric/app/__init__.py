from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_migrate import Migrate
from dotenv import load_dotenv
import os

# Load environment variables from .env file
load_dotenv()

db = SQLAlchemy()
login = LoginManager()
limiter = Limiter(key_func=get_remote_address)
migrate = Migrate()

def create_app():
    app = Flask(__name__)
    app.config.from_object('config.Config')

    db.init_app(app)
    login.init_app(app)
    limiter.init_app(app)
    migrate.init_app(app, db)

    login.login_view = 'login'
    
    with app.app_context():
        from app import routes, models

    # Add shell context processor
    @app.shell_context_processor
    def make_shell_context():
        return {
            'db': db,
            'User': models.User,
            'Audio': models.Audio,
            'Payment': models.Payment,
            'Faculty': models.Faculty,
            'Course': models.Course,
            'Purchase': models.Purchase
        }

    return app
