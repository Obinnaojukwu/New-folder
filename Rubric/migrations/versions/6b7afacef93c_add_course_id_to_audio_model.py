"""Add course_id to Audio model

Revision ID: 6b7afacef93c
Revises: dc20d2dd2717
Create Date: 2025-01-14 23:43:14.227456

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '6b7afacef93c'
down_revision = 'dc20d2dd2717'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('audio', schema=None) as batch_op:
        batch_op.add_column(sa.Column('course_id', sa.Integer(), nullable=False))
        batch_op.create_foreign_key('fk_audio_course', 'course', ['course_id'], ['id'])


def downgrade():
    with op.batch_alter_table('audio', schema=None) as batch_op:
        batch_op.drop_constraint('fk_audio_course', type_='foreignkey')
        batch_op.drop_column('course_id')