import Foundation

/// Contains the Terms of Service content for the Booki app
/// Used by UserAgreementView to display summary and full terms
enum TermsOfService {

    /// Current version of the agreement
    /// Note: AgreementService.currentAgreementVersion should match this
    static let version = "1.0"

    /// Summary text shown on the main agreement screen
    static let summary: String = """
        IMPORTANT: Please read carefully before continuing.

        Booki is a record-keeping and bet management tool. By using Booki, you acknowledge and agree that:

        • Booki does NOT place, accept, or process bets on your behalf
        • Booki does NOT hold, transfer, or process any money or payments
        • All financial arrangements between bookies and players occur entirely outside this app
        • Booki serves only as an organizational tool to track bets and balances
        • You are solely responsible for ensuring your activities comply with all applicable local, state, and federal laws
        • Booki makes no representations about the legality of sports betting in your jurisdiction

        This app is provided for record-keeping and entertainment purposes only. Booki is not a licensed sportsbook, gambling operator, or financial institution.

        By continuing, you confirm that you are at least 18 years old (or the legal age in your jurisdiction) and accept these terms.
        """

    /// Full Terms of Service document shown in the detail sheet
    static let fullTerms: String = """
        BOOKI TERMS OF SERVICE

        Last Updated: January 2026
        Version: \(version)

        1. ACCEPTANCE OF TERMS

        By accessing or using the Booki application ("App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.

        2. DESCRIPTION OF SERVICE

        Booki is a record-keeping and bet management tool designed to help users track bets and balances. Booki does NOT:
        - Place, accept, or process bets on behalf of users
        - Hold, transfer, or process any money or payments
        - Function as a sportsbook, gambling operator, or financial institution

        All financial arrangements between users occur entirely outside this App. Booki serves only as an organizational tool.

        3. USER RESPONSIBILITIES

        You are solely responsible for:
        - Ensuring your activities comply with all applicable local, state, and federal laws
        - Any financial arrangements made outside of this App
        - Maintaining the security of your account credentials
        - The accuracy of any data you enter into the App

        Booki makes no representations about the legality of sports betting in your jurisdiction. It is your responsibility to determine whether your use of this App is lawful.

        4. AGE REQUIREMENT

        You must be at least 18 years old (or the legal age in your jurisdiction) to use this App. By using this App, you represent and warrant that you meet this age requirement.

        5. DISCLAIMER OF WARRANTIES

        THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

        BOOKI MAKES NO REPRESENTATIONS OR WARRANTIES THAT:
        - The App will be uninterrupted, timely, secure, or error-free
        - The results obtained from using the App will be accurate or reliable
        - Any errors in the App will be corrected

        6. LIMITATION OF LIABILITY

        IN NO EVENT SHALL BOOKI, ITS OFFICERS, DIRECTORS, EMPLOYEES, OR AGENTS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING WITHOUT LIMITATION, LOSS OF PROFITS, DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES, ARISING OUT OF OR IN CONNECTION WITH:
        - Your access to or use of (or inability to access or use) the App
        - Any conduct or content of any third party
        - Any financial losses or disputes arising from arrangements made outside the App
        - Unauthorized access, use, or alteration of your data

        7. DATA USAGE AND PRIVACY

        Booki may collect and store data necessary for the operation of the App, including but not limited to:
        - Account information (email, authentication data)
        - Bet records and balance information
        - Usage data and analytics

        Your data is used solely for providing and improving the service. We do not sell your personal data to third parties. Data may be stored on cloud servers to enable synchronization across devices.

        8. ACCOUNT TERMINATION

        Booki reserves the right to terminate or suspend your access to the App at any time, for any reason, without prior notice. You may also delete your account at any time through the App settings.

        Upon termination, your right to use the App will immediately cease. All provisions of these Terms which by their nature should survive termination shall survive, including ownership provisions, warranty disclaimers, and limitations of liability.

        9. CHANGES TO TERMS

        Booki may modify these Terms at any time. When we make material changes, we will notify you through the App. Your continued use of the App after such modifications constitutes your acceptance of the updated Terms.

        If you do not agree to the modified Terms, you must stop using the App and may delete your account.

        10. GOVERNING LAW

        These Terms shall be governed by and construed in accordance with the laws of the jurisdiction in which the App operator is located, without regard to its conflict of law provisions.

        11. SEVERABILITY

        If any provision of these Terms is held to be invalid or unenforceable, such provision shall be struck and the remaining provisions shall be enforced to the fullest extent under law.

        12. ENTIRE AGREEMENT

        These Terms constitute the entire agreement between you and Booki regarding the use of the App, superseding any prior agreements between you and Booki relating to the App.

        13. CONTACT

        For questions about these Terms, please contact support through the App.

        BY USING BOOKI, YOU ACKNOWLEDGE THAT YOU HAVE READ THESE TERMS OF SERVICE, UNDERSTAND THEM, AND AGREE TO BE BOUND BY THEM.
        """
}
