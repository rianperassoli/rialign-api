class User < ApplicationRecord
  has_secure_password

  has_many :accounts,      dependent: :destroy
  has_many :credit_cards,  dependent: :destroy
  has_many :categories,    dependent: :destroy
  has_many :imports,       dependent: :destroy
  has_many :transactions,  dependent: :destroy

  before_validation :normalize_email

  validates :name, presence: true
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  private

  def normalize_email
    self.email = email.to_s.downcase.strip
  end
end
