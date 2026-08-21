import { Controller } from "@hotwired/stimulus"

// Checkout: crédito é opcional (checkbox liga/desliga). Quando o crédito cobre
// o total, o bloco de checkout (Pix/cartão) some — pagamento 100% com crédito.
export default class extends Controller {
  static targets = ["input", "toggle", "dot", "amountWrap", "usedField", "usedRow", "usedAmount", "due", "pix", "submit"]
  static values  = { total: Number, balance: Number }

  connect() { this.recompute() }

  recompute() {
    const total     = this.totalValue
    const balance   = this.balanceValue
    const useCredit = !this.hasToggleTarget || this.toggleTarget.checked

    if (this.hasAmountWrapTarget) this.amountWrapTarget.style.display = useCredit ? "" : "none"
    if (this.hasDotTarget)        this.dotTarget.style.opacity        = useCredit ? "1" : "0"

    let requested = 0
    if (useCredit) {
      const raw = this.hasInputTarget ? this.inputTarget.value.trim() : ""
      requested = raw === "" ? Math.min(balance, total) : Math.round(parseFloat(raw.replace(",", ".")) * 100)
      if (isNaN(requested) || requested < 0) requested = 0
    }

    const used = Math.min(requested, balance, total)
    const due  = total - used

    if (this.hasUsedFieldTarget)  this.usedFieldTarget.textContent  = this.fmt(used)
    if (this.hasUsedAmountTarget) this.usedAmountTarget.textContent = this.fmt(used)
    if (this.hasDueTarget)        this.dueTarget.textContent        = this.fmt(due)
    if (this.hasUsedRowTarget)    this.usedRowTarget.style.display  = used > 0 ? "" : "none"
    if (this.hasPixTarget)        this.pixTarget.style.display      = due > 0 ? "" : "none"
    if (this.hasSubmitTarget)     this.submitTarget.value           = due === 0 ? "Confirmar reserva" : "Pagar"
  }

  fmt(cents) {
    return "R$ " + (cents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
