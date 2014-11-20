class PaymentAddress < ActiveRecord::Base
  include Currencible
  belongs_to :account

  before_create :bts_gen_address, if: :bts_address?
  after_commit :gen_address, on: :create, unless: :bts_address?

  has_many :transactions, class_name: 'PaymentTransaction', foreign_key: 'address', primary_key: 'address'

  validates_uniqueness_of :address, allow_nil: true

  def bts_address?
    account && %w(btsx bitcny dns yun).include?(account.currency)
  end

  def bts_gen_address
    return if address
    self.address = "#{currency_obj.deposit_account}|#{self.class.construct_memo(account)}"
  end

  def gen_address
    return if address

    payload = { payment_address_id: id, currency: currency }
    attrs   = { persistent: true }
    AMQPQueue.enqueue(:deposit_coin_address, payload, attrs)
  end

  def memo
    address && address.split('|', 2).last
  end

  def deposit_address
    currency_obj[:deposit_account] || address
  end

  def trigger_deposit_address
    ::Pusher["private-#{account.member.sn}"].trigger_async('deposit_address', {type: 'create', attributes: as_json})
  end

  def self.construct_memo(obj)
    member = obj.is_a?(Account) ? obj.member : obj
    checksum = member.created_at.to_i.to_s[-3..-1]
    "#{member.id}#{checksum}"
  end

  def self.destruct_memo(memo)
    member_id = memo[0...-3]
    checksum  = memo[-3..-1]

    member = Member.find_by_id member_id
    return nil unless member
    return nil unless member.created_at.to_i.to_s[-3..-1] == checksum
    member
  end

end
