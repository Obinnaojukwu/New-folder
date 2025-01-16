"""Add is_admin to User model

Revision ID: dc20d2dd2717
Revises: 89b49516eee4
Create Date: 2025-01-14 22:22:20.123456

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'dc20d2dd2717'
down_revision = '89b49516eee4'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('user', schema=None) as batch_op:
        batch_op.add_column(sa.Column('is_admin', sa.Boolean(), nullable=True))
        # Ensure constraints have names
        batch_op.create_unique_constraint('uq_user_email', ['email'])

def downgrade():
    with op.batch_alter_table('user', schema=None) as batch_op:
        batch_op.drop_constraint('uq_user_email', type_='unique')
        batch_op.drop_column('is_admin')