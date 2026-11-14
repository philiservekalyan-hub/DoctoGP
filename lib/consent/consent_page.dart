// lib/consent/consent_page.dart
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// DATA MODEL
/// ---------------------------------------------------------------------------

class ConsentRecord {
  final String noticeVersion;
  final DateTime timestamp;
  final List<String> acceptedPurposes;
  final String patientName;
  final String languageCode;

  // Minor-only fields. Null for adults.
  final String? guardianName;
  final String? guardianRelationship;
  final String? dateOfBirth;

  const ConsentRecord({
    required this.noticeVersion,
    required this.timestamp,
    required this.acceptedPurposes,
    required this.patientName,
    required this.languageCode,
    this.guardianName,
    this.guardianRelationship,
    this.dateOfBirth,
  });

  bool get isMinorConsent => guardianName != null;

  Map<String, dynamic> toMap() => {
        'consent_version': noticeVersion,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'accepted_purposes': acceptedPurposes,
        'patient_name': patientName,
        'language': languageCode,
        'action': 'granted',
        if (guardianName != null) 'guardian_name': guardianName,
        if (guardianRelationship != null)
          'guardian_relationship': guardianRelationship,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        'minor': isMinorConsent,
      };
}

enum ConsentLanguage {
  english('en', 'English'),
  hindi('hi', 'हिन्दी');

  final String code;
  final String label;
  const ConsentLanguage(this.code, this.label);
}

/// ---------------------------------------------------------------------------
/// LOCALISED STRINGS
/// ---------------------------------------------------------------------------

const Map<ConsentLanguage, Map<String, String>> _kStrings = {
  ConsentLanguage.english: {
    'appTitle': 'Patient Consent',
    'language': 'Language',
    'intro':
        'Please read this notice carefully before creating your account. Your '
            'doctor\'s clinic (the "Clinic") needs your permission to collect and '
            'use your personal health information to provide you with care. You '
            'may refuse or withdraw consent, but this may affect the services the '
            'Clinic can provide.',
    's1_title': '1. Who is collecting your data?',
    's1_body': 'The Data Fiduciary responsible for your data is:\n{clinic}\n'
        '{address}\n{contact}',
    's2_title': '2. What personal data we collect',
    's2_body':
        '• Identity & Contact Data: full name, date of birth, gender, phone '
            'number, email address, residential address.\n'
            '• Health Data: medical history, symptoms, diagnoses, treatment '
            'records, prescription details, laboratory reports and other '
            'clinical information.\n'
            '• Appointment & Billing Data: appointment dates and times, '
            'consultation notes and billing/payment records.\n'
            '• Technical Data: device type, operating system and app usage logs '
            '(for security and functionality).',
    's3_title': '3. Why we need your data (Purpose of Processing)',
    's3_intro':
        'We will use your data only for the purposes you agree to below. Please '
            'tick each box to give your specific consent. You cannot use the app '
            'without consenting to Purpose 1.',
    'p1_title': 'Purpose 1: Provision of Clinical Care',
    'p1_body':
        'I consent to the Clinic collecting and using my identity, contact and '
            'health data to provide medical care. This includes maintaining my '
            'electronic health record, facilitating consultations, issuing '
            'prescriptions and coordinating necessary investigations. '
            'Legal basis: your consent.',
    'p2_title': 'Purpose 2: Appointment Management & Communication',
    'p2_body':
        'I consent to the Clinic using my contact data to send me appointment '
            'reminders, confirmations and follow-up messages via SMS, email or '
            'WhatsApp.',
    'p3_title': 'Purpose 3: Billing & Payment Processing',
    'p3_body':
        'I consent to the Clinic using my identity, contact and appointment data '
            'to process payments and maintain billing records.',
    'p4_title': 'Purpose 4: Optional Health Reminders & Updates',
    'p4_body':
        'I consent to the Clinic using my contact data to send me general health '
            'tips, preventive care reminders or information about Clinic '
            'services not related to a specific appointment. You can refuse this '
            'and still use the app.',
    'p5_title': 'Purpose 5: De-Identified Analytics for Pharmaceutical Research',
    'p5_body':
        'I consent to the Clinic sharing my de-identified health data (with my '
            'name, contact details and other direct identifiers removed) with '
            'pharmaceutical companies and their analytics partners. This data '
            'will be used only to create aggregated reports and dashboards about '
            'treatment patterns, disease prevalence and medication outcomes. '
            'I understand that: (a) this is a commercial purpose and the '
            'pharmaceutical company may benefit financially; (b) my data will be '
            'de-identified before sharing; (c) the company will not use it to '
            'contact me or make individual care decisions; and (d) I can '
            'withdraw this consent at any time via Privacy Settings without '
            'affecting my medical treatment.',
    'p6_title': 'Purpose 6: Emergency Contact Notifications for Missed Doses',
    'p6_body':
        'I consent to this app using my emergency contact\'s phone number to '
            'send an SMS if I miss a scheduled medication dose past its grace '
            'window. The SMS will include my name, the medication name, the dose '
            'and the scheduled time. I understand that: (a) my emergency contact '
            'has given their permission to receive such messages; (b) I can '
            'change or remove my emergency contact at any time; (c) I can '
            'withdraw this consent at any time via Privacy Settings, which '
            'disables all such alerts immediately; and (d) this is an optional '
            'convenience and does not replace professional medical judgment. '
            'Legal basis: your consent.',
    's4_title': '4. Your Rights and How to Exercise Them',
    's4_body':
        'You can exercise these rights through the app\'s Privacy Settings or by '
            'contacting us using the details in Section 5.',
    'r1':
        'Right to Access & Correction: request a copy of your data and ask us to '
            'correct inaccuracies.',
    'r2':
        'Right to Erasure: request deletion of your data, subject to legal '
            'retention requirements for medical records.',
    'r3':
        'Right to Withdraw Consent: withdraw at any time. Withdrawing consent is '
            'as easy as giving it — via Privacy Settings in the app or by '
            'contacting us. Withdrawal does not affect the lawfulness of '
            'processing before withdrawal. If you withdraw consent for mandatory '
            'purposes, we may not be able to continue providing services through '
            'this app.',
    'r4':
        'Right to Grievance Redressal: if you have a complaint, contact our '
            'Grievance Officer first. If not satisfied, you may lodge a complaint '
            'with the Data Protection Board of India.',
    's5_title': '5. Contact Us',
    's5_body': 'For questions, to exercise your rights, or to raise a grievance:'
        '\nGrievance Officer: {name}\nEmail: {email}\nPhone: {phone}',
    'decl_title': 'Declaration and Affirmative Consent',
    'decl_body':
        'I have read and understood this notice. I am providing my consent '
            'freely and voluntarily. I understand that I can withdraw my consent '
            'at any time.',
    'final_label':
        'I agree and give my consent to the processing of my personal data as '
            'described above.',
    'name_label': 'Patient name',
    'child_name_label': 'Patient (child) name',
    'guardian_name_label': 'Parent / guardian full name',
    'guardian_rel_label': 'Relationship to the child',
    'guardian_rel_hint': 'e.g. Mother, Father, Legal guardian',
    'err_name': 'Please enter the patient\'s name.',
    'err_guardian_name': 'Please enter the guardian\'s name.',
    'err_guardian_rel': 'Please state your relationship to the child.',
    'submit': 'Give Consent & Continue',
    'decline': 'Decline',
    'scroll_hint': 'Please scroll to the end of this notice to continue.',
    'err_purpose1': 'Consent to Purpose 1 is required to use this app.',
    'err_final': 'Please tick the final consent box.',
    'err_scroll': 'Please read the full notice before giving consent.',
    'badge_required': 'REQUIRED',
    'badge_optional': 'OPTIONAL',
    'decline_title': 'Cannot continue without consent',
    'decline_body':
        'Consent to Purpose 1 is required to use this app. You can log in later '
            'and give consent then.',
    'cancel': 'Cancel',
    'ok': 'OK',
    'minor_notice':
        'This patient is under 18. Under the DPDP Act, 2023, a parent or '
            'lawful guardian must give consent on the child\'s behalf. '
            'Please enter the guardian\'s details below. Optional marketing '
            'and pharmaceutical-analytics consents are not offered for '
            'patients under 18.',
  },
  ConsentLanguage.hindi: {
    'appTitle': 'रोगी सहमति',
    'language': 'भाषा',
    'intro':
        'कृपया अपना खाता बनाने से पहले इस सूचना को ध्यान से पढ़ें। आपके डॉक्टर का '
            'क्लिनिक ("क्लिनिक") आपको देखभाल प्रदान करने के लिए आपकी व्यक्तिगत '
            'स्वास्थ्य जानकारी एकत्र करने और उपयोग करने के लिए आपकी अनुमति चाहता '
            'है। आप सहमति देने से मना कर सकते हैं या इसे वापस ले सकते हैं, लेकिन '
            'इससे क्लिनिक द्वारा प्रदान की जाने वाली सेवाएँ प्रभावित हो सकती हैं।',
    's1_title': '1. आपका डेटा कौन एकत्र कर रहा है?',
    's1_body': 'आपके डेटा के लिए उत्तरदायी डेटा फ़िड्यूशियरी है:\n{clinic}\n'
        '{address}\n{contact}',
    's2_title': '2. हम कौन-सा व्यक्तिगत डेटा एकत्र करते हैं',
    's2_body':
        '• पहचान एवं संपर्क डेटा: पूरा नाम, जन्म तिथि, लिंग, फ़ोन नंबर, ईमेल '
            'पता, आवासीय पता।\n'
            '• स्वास्थ्य डेटा: चिकित्सा इतिहास, लक्षण, निदान, उपचार रिकॉर्ड, '
            'पर्चे का विवरण, प्रयोगशाला रिपोर्ट और अन्य नैदानिक जानकारी।\n'
            '• अपॉइंटमेंट एवं बिलिंग डेटा: अपॉइंटमेंट की तिथियाँ और समय, परामर्श '
            'नोट्स और बिलिंग/भुगतान रिकॉर्ड।\n'
            '• तकनीकी डेटा: डिवाइस प्रकार, ऑपरेटिंग सिस्टम और ऐप उपयोग लॉग '
            '(सुरक्षा और कार्यक्षमता के लिए)।',
    's3_title': '3. हमें आपके डेटा की आवश्यकता क्यों है (प्रसंस्करण का उद्देश्य)',
    's3_intro':
        'हम आपके डेटा का उपयोग केवल उन उद्देश्यों के लिए करेंगे जिनके लिए आप नीचे '
            'सहमति देते हैं। कृपया अपनी विशिष्ट सहमति देने के लिए प्रत्येक बॉक्स को '
            'टिक करें। उद्देश्य 1 के लिए सहमति के बिना आप ऐप का उपयोग नहीं कर सकते।',
    'p1_title': 'उद्देश्य 1: नैदानिक देखभाल प्रदान करना',
    'p1_body':
        'मैं क्लिनिक को चिकित्सा देखभाल प्रदान करने के लिए अपनी पहचान, संपर्क और '
            'स्वास्थ्य डेटा एकत्र करने और उपयोग करने की सहमति देता/देती हूँ। इसमें '
            'मेरा इलेक्ट्रॉनिक स्वास्थ्य रिकॉर्ड बनाए रखना, परामर्श की सुविधा, पर्चे '
            'जारी करना और आवश्यक जाँचों का समन्वय शामिल है। कानूनी आधार: आपकी सहमति।',
    'p2_title': 'उद्देश्य 2: अपॉइंटमेंट प्रबंधन एवं संचार',
    'p2_body':
        'मैं क्लिनिक को SMS, ईमेल या WhatsApp के माध्यम से अपॉइंटमेंट रिमाइंडर, '
            'पुष्टि और फ़ॉलो-अप संदेश भेजने के लिए अपने संपर्क डेटा का उपयोग करने की '
            'सहमति देता/देती हूँ।',
    'p3_title': 'उद्देश्य 3: बिलिंग एवं भुगतान प्रसंस्करण',
    'p3_body':
        'मैं क्लिनिक को भुगतान संसाधित करने और बिलिंग रिकॉर्ड बनाए रखने के लिए अपनी '
            'पहचान, संपर्क और अपॉइंटमेंट डेटा का उपयोग करने की सहमति देता/देती हूँ।',
    'p4_title': 'उद्देश्य 4: वैकल्पिक स्वास्थ्य रिमाइंडर एवं अपडेट',
    'p4_body':
        'मैं क्लिनिक को सामान्य स्वास्थ्य सुझाव, निवारक देखभाल रिमाइंडर या किसी '
            'विशिष्ट अपॉइंटमेंट से संबंधित न होने वाली क्लिनिक सेवाओं की जानकारी '
            'भेजने के लिए अपने संपर्क डेटा का उपयोग करने की सहमति देता/देती हूँ। आप '
            'इससे मना कर सकते हैं और फिर भी ऐप का उपयोग कर सकते हैं।',
    'p5_title': 'उद्देश्य 5: फार्मास्युटिकल अनुसंधान के लिए विबंधित विश्लेषण',
    'p5_body':
        'मैं क्लिनिक को फार्मास्युटिकल कंपनियों और उनके विश्लेषण साझेदारों के साथ अपने '
            'विबंधित स्वास्थ्य डेटा (जिसमें से मेरा नाम, संपर्क विवरण और अन्य प्रत्यक्ष '
            'पहचानकर्ता हटा दिए गए हैं) साझा करने की सहमति देता/देती हूँ। इस डेटा का '
            'उपयोग केवल उपचार पैटर्न, रोग व्यापकता और दवा परिणामों के बारे में '
            'समेकित रिपोर्ट और डैशबोर्ड बनाने के लिए किया जाएगा। मैं समझता/समझती हूँ '
            'कि: (क) यह एक वाणिज्यिक उद्देश्य है और फार्मास्युटिकल कंपनी को वित्तीय लाभ '
            'हो सकता है; (ख) साझा करने से पहले मेरा डेटा विबंधित किया जाएगा; (ग) '
            'कंपनी इसका उपयोग मुझसे संपर्क करने या व्यक्तिगत देखभाल निर्णय लेने के लिए '
            'नहीं करेगी; और (घ) मैं बिना किसी चिकित्सा उपचार को प्रभावित किए किसी भी '
            'समय प्राइवेसी सेटिंग्स के माध्यम से यह सहमति वापस ले सकता/सकती हूँ।',
    'p6_title':
        'उद्देश्य 6: छूटी हुई खुराक के लिए आपातकालीन संपर्क सूचनाएँ',
    'p6_body':
        'मैं सहमति देता/देती हूँ कि यदि मैं निर्धारित दवा की खुराक ग्रेस अवधि के बाद भी '
            'नहीं ले पाता/पाती, तो यह ऐप मेरे आपातकालीन संपर्क के फ़ोन नंबर पर SMS '
            'भेज सकता है। SMS में मेरा नाम, दवा का नाम, खुराक और निर्धारित समय शामिल '
            'होगा। मैं समझता/समझती हूँ कि: (क) मेरे आपातकालीन संपर्क ने ऐसे संदेश प्राप्त '
            'करने की अनुमति दी है; (ख) मैं किसी भी समय अपना आपातकालीन संपर्क बदल या '
            'हटा सकता/सकती हूँ; (ग) मैं किसी भी समय प्राइवेसी सेटिंग्स के माध्यम से यह '
            'सहमति वापस ले सकता/सकती हूँ, जिससे ऐसे सभी अलर्ट तुरंत बंद हो जाएँगे; और '
            '(घ) यह एक वैकल्पिक सुविधा है और पेशेवर चिकित्सा निर्णय का विकल्प नहीं है। '
            'कानूनी आधार: आपकी सहमति।',
    's4_title': '4. आपके अधिकार और उनका प्रयोग कैसे करें',
    's4_body':
        'आप ऐप की "प्राइवेसी सेटिंग्स" के माध्यम से या धारा 5 में दिए गए विवरण का '
            'उपयोग करके हमसे संपर्क करके इन अधिकारों का प्रयोग कर सकते हैं।',
    'r1':
        'पहुँच एवं सुधार का अधिकार: अपने डेटा की प्रति का अनुरोध करें और किसी भी '
            'त्रुटि को ठीक करने के लिए कहें।',
    'r2':
        'मिटाने का अधिकार: चिकित्सा रिकॉर्ड के लिए कानूनी प्रतिधारण आवश्यकताओं के '
            'अधीन, अपने डेटा को हटाने का अनुरोध करें।',
    'r3':
        'सहमति वापस लेने का अधिकार: आप किसी भी समय अपनी सहमति वापस ले सकते हैं। '
            'सहमति वापस लेना उतना ही आसान है जितना देना — ऐप की प्राइवेसी सेटिंग्स के '
            'माध्यम से या हमसे संपर्क करके। वापसी से पहले के प्रसंस्करण की वैधता पर '
            'कोई प्रभाव नहीं पड़ेगा। यदि आप अनिवार्य उद्देश्यों के लिए सहमति वापस लेते '
            'हैं, तो हम इस ऐप के माध्यम से सेवाएँ प्रदान करना जारी नहीं रख सकते।',
    'r4':
        'शिकायत निवारण का अधिकार: यदि आपको कोई शिकायत है, तो कृपया पहले हमारे '
            'शिकायत अधिकारी से संपर्क करें। यदि संतुष्ट नहीं हैं, तो आप भारत के डेटा '
            'संरक्षण बोर्ड के पास शिकायत दर्ज कर सकते हैं।',
    's5_title': '5. हमसे संपर्क करें',
    's5_body': 'प्रश्नों, अधिकारों के प्रयोग या शिकायत के लिए:\nशिकायत अधिकारी: '
        '{name}\nईमेल: {email}\nफ़ोन: {phone}',
    'decl_title': 'घोषणा एवं सकारात्मक सहमति',
    'decl_body':
        'मैंने इस सूचना को पढ़ और समझ लिया है। मैं अपनी सहमति स्वेच्छा से और बिना किसी '
            'दबाव के दे रहा/रही हूँ। मैं समझता/समझती हूँ कि मैं किसी भी समय अपनी सहमति '
            'वापस ले सकता/सकती हूँ।',
    'final_label':
        'मैं सहमत हूँ और ऊपर वर्णित रूप से अपने व्यक्तिगत डेटा के प्रसंस्करण के लिए '
            'अपनी सहमति देता/देती हूँ।',
    'name_label': 'रोगी का नाम',
    'child_name_label': 'रोगी (बच्चे) का नाम',
    'guardian_name_label': 'माता-पिता / अभिभावक का पूरा नाम',
    'guardian_rel_label': 'बच्चे से संबंध',
    'guardian_rel_hint': 'जैसे माता, पिता, वैध अभिभावक',
    'err_name': 'कृपया रोगी का नाम दर्ज करें।',
    'err_guardian_name': 'कृपया अभिभावक का नाम दर्ज करें।',
    'err_guardian_rel': 'कृपया बच्चे से अपना संबंध बताएं।',
    'submit': 'सहमति दें और जारी रखें',
    'decline': 'अस्वीकार करें',
    'scroll_hint': 'जारी रखने के लिए कृपया इस सूचना को अंत तक स्क्रॉल करें।',
    'err_purpose1': 'इस ऐप का उपयोग करने के लिए उद्देश्य 1 के लिए सहमति आवश्यक है।',
    'err_final': 'कृपया अंतिम सहमति बॉक्स को टिक करें।',
    'err_scroll': 'सहमति देने से पहले कृपया पूरी सूचना पढ़ें।',
    'badge_required': 'अनिवार्य',
    'badge_optional': 'वैकल्पिक',
    'decline_title': 'सहमति के बिना जारी नहीं रखा जा सकता',
    'decline_body':
        'इस ऐप का उपयोग करने के लिए उद्देश्य 1 के लिए सहमति आवश्यक है। आप बाद में '
            'लॉग इन करके सहमति दे सकते हैं।',
    'cancel': 'रद्द करें',
    'ok': 'ठीक है',
    'minor_notice':
        'यह रोगी 18 वर्ष से कम आयु का है। DPDP अधिनियम, 2023 के अंतर्गत, बच्चे की ओर '
            'से माता-पिता या वैध अभिभावक को सहमति देनी होगी। कृपया नीचे अभिभावक का '
            'विवरण दर्ज करें। 18 वर्ष से कम आयु के रोगियों के लिए वैकल्पिक मार्केटिंग '
            'और फार्मास्युटिकल-विश्लेषण सहमति प्रदान नहीं की जाती।',
  },
};

/// ---------------------------------------------------------------------------
/// THE PAGE
/// ---------------------------------------------------------------------------

class ConsentPage extends StatefulWidget {
  final String clinicName;
  final String clinicAddress;
  final String clinicContact;
  final String grievanceOfficer;
  final String grievanceEmail;
  final String grievancePhone;
  final String noticeVersion;
  final bool requireScrollToEnd;
  final Future<void> Function(ConsentRecord record)? onConsentGiven;
  final VoidCallback? onDeclined;

  /// When true, shows the guardian-consent branch, hides Purposes 4, 5 & 6,
  /// and requires guardian name + relationship.
  final bool isMinor;

  /// ISO-8601 DOB, recorded in the audit trail.
  final String? dateOfBirth;

  const ConsentPage({
    super.key,
    required this.clinicName,
    required this.clinicAddress,
    required this.clinicContact,
    required this.grievanceOfficer,
    required this.grievanceEmail,
    required this.grievancePhone,
    this.noticeVersion = '1.0',
    this.requireScrollToEnd = true,
    this.onConsentGiven,
    this.onDeclined,
    this.isMinor = false,
    this.dateOfBirth,
  });

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  ConsentLanguage _language = ConsentLanguage.english;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _guardianNameController = TextEditingController();
  final TextEditingController _guardianRelationshipController =
      TextEditingController();

  bool _scrolledToEnd = false;
  bool _submitting = false;

  bool _purpose1 = false;
  bool _purpose2 = false;
  bool _purpose3 = false;
  bool _purpose4 = false;
  bool _purpose5 = false;
  bool _purpose6 = false;

  bool _finalConsent = false;
  String? _nameError;
  String? _guardianNameError;
  String? _guardianRelError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _nameController.addListener(() {
      if (_nameError != null) setState(() => _nameError = null);
    });
    _guardianNameController.addListener(() {
      if (_guardianNameError != null) {
        setState(() => _guardianNameError = null);
      }
    });
    _guardianRelationshipController.addListener(() {
      if (_guardianRelError != null) {
        setState(() => _guardianRelError = null);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent <= 0) {
        setState(() => _scrolledToEnd = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _nameController.dispose();
    _guardianNameController.dispose();
    _guardianRelationshipController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrolledToEnd || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      setState(() => _scrolledToEnd = true);
    }
  }

  String _t(String key) {
    final raw = _kStrings[_language]![key] ??
        _kStrings[ConsentLanguage.english]![key] ??
        key;
    return raw
        .replaceAll('{clinic}', widget.clinicName)
        .replaceAll('{address}', widget.clinicAddress)
        .replaceAll('{contact}', widget.clinicContact)
        .replaceAll('{name}', widget.grievanceOfficer)
        .replaceAll('{email}', widget.grievanceEmail)
        .replaceAll('{phone}', widget.grievancePhone);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSubmit() async {
    if (widget.requireScrollToEnd && !_scrolledToEnd) {
      _snack(_t('err_scroll'));
      return;
    }
    if (!_purpose1) {
      _snack(_t('err_purpose1'));
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = _t('err_name'));
      return;
    }

    String? guardianName;
    String? guardianRelationship;

    if (widget.isMinor) {
      guardianName = _guardianNameController.text.trim();
      guardianRelationship = _guardianRelationshipController.text.trim();

      if (guardianName.isEmpty) {
        setState(() => _guardianNameError = _t('err_guardian_name'));
        return;
      }
      if (guardianRelationship.isEmpty) {
        setState(() => _guardianRelError = _t('err_guardian_rel'));
        return;
      }
      // Safety: never accept purposes 4, 5 or 6 for a minor.
      _purpose4 = false;
      _purpose5 = false;
      _purpose6 = false;
    }

    if (!_finalConsent) {
      _snack(_t('err_final'));
      return;
    }

    final purposes = <String>[
      if (_purpose1) 'purpose_1',
      if (_purpose2) 'purpose_2',
      if (_purpose3) 'purpose_3',
      if (!widget.isMinor && _purpose4) 'purpose_4',
      if (!widget.isMinor && _purpose5) 'purpose_5',
      if (!widget.isMinor && _purpose6) 'purpose_6',
    ];

    final record = ConsentRecord(
      noticeVersion: widget.noticeVersion,
      timestamp: DateTime.now(),
      acceptedPurposes: purposes,
      patientName: name,
      languageCode: _language.code,
      guardianName: guardianName,
      guardianRelationship: guardianRelationship,
      dateOfBirth: widget.dateOfBirth,
    );

    setState(() => _submitting = true);
    try {
      if (widget.onConsentGiven != null) {
        await widget.onConsentGiven!(record);
      }
      if (!mounted) return;
      Navigator.of(context).pop(record);
    } catch (e, st) {
      debugPrint('[CONSENT] save failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not save your consent: $e');
    }
  }

  Future<void> _handleDecline() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('decline_title')),
        content: Text(_t('decline_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('decline')),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) {
      widget.onDeclined?.call();
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium
        ?.copyWith(height: 1.55, color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('appTitle')),
        actions: [
          PopupMenuButton<ConsentLanguage>(
            icon: const Icon(Icons.translate),
            tooltip: _t('language'),
            onSelected: (l) => setState(() => _language = l),
            itemBuilder: (_) => ConsentLanguage.values
                .map((l) => PopupMenuItem(
                      value: l,
                      child: Row(
                        children: [
                          if (l == _language)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.check, size: 18),
                            ),
                          Text(l.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withOpacity(0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_t('intro'),
                          style: bodyStyle
                              ?.copyWith(color: theme.colorScheme.onSurface)),
                    ),
                    const SizedBox(height: 20),

                    _SectionTitle(_t('s1_title')),
                    Text(_t('s1_body'), style: bodyStyle),
                    const SizedBox(height: 20),

                    _SectionTitle(_t('s2_title')),
                    Text(_t('s2_body'), style: bodyStyle),
                    const SizedBox(height: 20),

                    _SectionTitle(_t('s3_title')),
                    Text(_t('s3_intro'), style: bodyStyle),

                    // ---- Minor notice ----
                    if (widget.isMinor) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.family_restroom, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_t('minor_notice'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    _ConsentTile(
                      value: _purpose1,
                      onChanged: (v) => setState(() => _purpose1 = v),
                      title: _t('p1_title'),
                      body: _t('p1_body'),
                      badge: _t('badge_required'),
                      badgeColor: theme.colorScheme.error,
                    ),
                    _ConsentTile(
                      value: _purpose2,
                      onChanged: (v) => setState(() => _purpose2 = v),
                      title: _t('p2_title'),
                      body: _t('p2_body'),
                      badge: _t('badge_optional'),
                      badgeColor: theme.colorScheme.outline,
                    ),
                    _ConsentTile(
                      value: _purpose3,
                      onChanged: (v) => setState(() => _purpose3 = v),
                      title: _t('p3_title'),
                      body: _t('p3_body'),
                      badge: _t('badge_optional'),
                      badgeColor: theme.colorScheme.outline,
                    ),
                    if (!widget.isMinor) ...[
                      _ConsentTile(
                        value: _purpose4,
                        onChanged: (v) => setState(() => _purpose4 = v),
                        title: _t('p4_title'),
                        body: _t('p4_body'),
                        badge: _t('badge_optional'),
                        badgeColor: theme.colorScheme.outline,
                      ),
                      _ConsentTile(
                        value: _purpose5,
                        onChanged: (v) => setState(() => _purpose5 = v),
                        title: _t('p5_title'),
                        body: _t('p5_body'),
                        badge: _t('badge_optional'),
                        badgeColor: theme.colorScheme.outline,
                      ),
                      _ConsentTile(
                        value: _purpose6,
                        onChanged: (v) => setState(() => _purpose6 = v),
                        title: _t('p6_title'),
                        body: _t('p6_body'),
                        badge: _t('badge_optional'),
                        badgeColor: theme.colorScheme.outline,
                      ),
                    ],
                    const SizedBox(height: 20),

                    _SectionTitle(_t('s4_title')),
                    Text(_t('s4_body'), style: bodyStyle),
                    const SizedBox(height: 8),
                    _Bullet(_t('r1'), style: bodyStyle),
                    _Bullet(_t('r2'), style: bodyStyle),
                    _Bullet(_t('r3'), style: bodyStyle),
                    _Bullet(_t('r4'), style: bodyStyle),
                    const SizedBox(height: 20),

                    _SectionTitle(_t('s5_title')),
                    Text(_t('s5_body'), style: bodyStyle),
                    const SizedBox(height: 20),
                    const Divider(),

                    const SizedBox(height: 12),
                    _SectionTitle(_t('decl_title')),
                    Text(_t('decl_body'), style: bodyStyle),
                    const SizedBox(height: 12),
                    _ConsentTile(
                      value: _finalConsent,
                      onChanged: (v) => setState(() => _finalConsent = v),
                      title: _t('final_label'),
                      body: '',
                      highlight: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: widget.isMinor
                            ? _t('child_name_label')
                            : _t('name_label'),
                        border: const OutlineInputBorder(),
                        errorText: _nameError,
                      ),
                    ),
                    if (widget.isMinor) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _guardianNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: _t('guardian_name_label'),
                          border: const OutlineInputBorder(),
                          errorText: _guardianNameError,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _guardianRelationshipController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: _t('guardian_rel_label'),
                          hintText: _t('guardian_rel_hint'),
                          border: const OutlineInputBorder(),
                          errorText: _guardianRelError,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _submitting ? null : _handleDecline,
                      child: Text(_t('decline')),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.requireScrollToEnd && !_scrolledToEnd)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_downward,
                              size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _t('scroll_hint'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _handleSubmit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_t('submit')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _Bullet(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String body;
  final String? badge;
  final Color? badgeColor;
  final bool highlight;

  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.body,
    this.badge,
    this.badgeColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: highlight && value
            ? theme.colorScheme.primaryContainer.withOpacity(0.35)
            : theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? theme.colorScheme.primary
              : theme.dividerColor.withOpacity(0.6),
          width: value ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? theme.colorScheme.outline)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeColor ?? theme.colorScheme.outline,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}