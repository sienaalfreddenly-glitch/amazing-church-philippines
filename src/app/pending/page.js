export default function Pending() {
  return (
    <div className="max-w-lg mx-auto card mt-10 text-center">
      <h1 className="text-2xl mb-2">Waiting for approval</h1>
      <p className="text-ink/70">
        Thank you for signing up! An admin will review your account shortly.
        You'll be able to post and start discussions as soon as you're approved.
      </p>
    </div>
  );
}
