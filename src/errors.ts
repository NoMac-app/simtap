/** A failure the agent can act on: what went wrong, and the next step. */
export class ToolError extends Error {
  readonly next?: string;

  constructor(message: string, next?: string) {
    super(message);
    this.next = next;
  }

  toText(): string {
    return this.next ? `${this.message}\nNext: ${this.next}` : this.message;
  }
}
