/*****************************************************************************************************************
Name        : SRV_CaseHandler
Author      : Appshark
Created Date: 30th October 2017
Description : Handler class for case related functionality 
Test Class  : SRV_CaseHandler_Test
*******************************************************************************************************************/

public class SRV_CaseHandler {
    public static Boolean isTriggerExecuted = true;

    /*
     * Name: RestrictCaseCommentCreation
     * Description : Restrict sales user from creating case comments on service cases
     * Parameters : List of Case comments
     */

    public static void RestrictCaseCommentCreation(List<caseComment> lstCaseComment) {
        try{

             Id profileId = UserInfo.getProfileId();
            String profileName =[Select Id, Name from Profile where Id=:profileId].Name;
            system.debug('Profile Name'+profileName);
            
            //Filter the record types that are applicable
            map<string,id> mapRecTypes = new map<string,id>();
             for (Recordtype objRecType : [Select id,Name From RecordType where sobjecttype = 'Case' and 
                                            DeveloperName Like 'SRV%'])
             {
                 mapRecTypes.put(objRecType.Name, objRecType.id);
             }
            
            system.debug('mapRecTypes' + mapRecTypes);
            map<id,boolean> mapServiceCase = new map<id,boolean>();
            set<string> setCaseId = new set<string>();
            for(CaseComment objCaseComm : lstCaseComment)
            {
                system.debug('parent ----'+objCaseComm.ParentId);
                setCaseId.add(objCaseComm.ParentId);
            }
            /*Commented this and added it to the list
            for(Case objCase : [select id from case where recordtypeid IN : lstRecTypes and id IN: setCaseId])
            {
                mapServiceCase.put(objCase.id,true);
            }*/
            //Added this statement
            //list<id> lstcase = [select id from case where recordtypeid IN : lstRecTypes and id IN: setCaseId];
            list<id> lstServicecase = new list<id>();
            if(!mapRecTypes.isempty())
            {
            for(Case objCase : [select id,recordtype.name,recordtypeid from case 
                                where recordtypeid IN : mapRecTypes.keyset() and id IN: setCaseId])
            {
                if(mapRecTypes.get(objCase.RecordType.Name) != null && objCase.recordtypeid == mapRecTypes.get(objCase.RecordType.Name))
                    lstServicecase.add(objCase.id);
            }
            for(CaseComment objcasecm : lstCaseComment)
            {
                system.debug('profileName---'+profileName+'--mapServiceCase.get(objcasecm.ParentID)---'+mapServiceCase.get(objcasecm.ParentID));
                if(!lstServicecase.isempty() && lstServicecase.contains(objcasecm.ParentID) &&
                  (profileName == 'GCI Sales Manager' || profileName == 'GCI Sales User' || profileName == 'GCI-B Sales Support Admin' ||
                   profileName == 'GCI-B Solution Engineer' || profileName == 'SalesOps User' || profileName == 'VAR User' ))
                {
                    objcasecm.addError('Case Comments cannot be added');
                }
            }
            }
        }
        catch(exception ex)
        {
            throw new ApexException('Exception:' +Ex.getMessage());
        }
    }
    
     /*
     * Name: DefaultCaseValues
     * Description : To rollup cases on account in different related lists(service cases, opportunity cases, account cases)
     * Parameters : List of Cases
     */
    public static void DefaultCaseValues(list<Case> lstCases)
    {
        try{
            set<id> setConIds = new set<id>();
            set<id> setAcctIds = new set<id>();
            set<string> setRecTypes = new set<string>();
            map<id, id> mapAcctIds = new map<id, id>(); //to store the respective accountid for each contact id.
            //Get the list of Market Segments
            map<id, string> mapMarketSegments = new map<id, string>(); 
            //Prepare the map of accountid and it's parentid to rollup the cases to the parent
            map<id, id> mapParentAcctIds = new map<id, id>();
            
            for (Case objCase : lstCases)
            {
                //If AccountID exists, then it is thru omniscript or standard
                if (objCase.AccountId != null)
                    setAcctIds.add(objcase.AccountId);
                else//If AccountID doesn't exist, then it is email2case
                    setConIds.add(objCase.ContactId);
                
                //Store the record type Ids, to prepop the related list
                setRecTypes.add(objCase.RecordTypeId);
            }            
            system.debug('Entered DefaultCasevalues ');
            
            for (Contact objAcct : [select AccountId, Account.ParentId, Account.Market_Segment__c from Contact where 
                                    Id in :setConIds or AccountID in :setAcctIds])
            {
                mapMarketSegments.put(objAcct.AccountId, objAcct.Account.Market_Segment__c);
                
                mapAcctIds.put(objAcct.id, objAcct.AccountId); 
                if (objAcct.Account.ParentId != null)
                    mapParentAcctIds.put(objAcct.AccountId, objAcct.Account.ParentId);
            }
            system.debug('mapparentids ' + mapParentAcctIds);
            
            map<id, string> mapRecTypes = new map<id, string>();
            for (RecordType objRecType : [select id, DeveloperName from RecordType where id in :setRecTypes])
            {
                mapRecTypes.put(objRecType.Id, objRecType.DeveloperName);
            }
            system.debug('mapRecTypes ' + mapRecTypes);
            system.debug('map of marketsegments ' + mapMarketSegments);
            system.debug('lstCases' + lstCases);
            for (Case objNewCase : lstCases)
            {
                string strRecordType = mapRecTypes.get(objNewCase.RecordTypeId);
                system.debug('strRecordType ' + strRecordType + objNewCase.ContactId);
                //Check if Account is associated with the Case
                string strAccountID = '';
                string strParentAccountID = '';
                if (objNewCase.AccountId != null) //NonEmail2case should be linked with Account - Omniscript/Manual Cases
                    strAccountID = objNewCase.AccountId;
                else if (objNewCase.contactId != null && mapAcctIds.get(objNewCase.contactId) !=null) //Email2Cases should be linked based on Contact
                    strAccountID = mapAcctIds.get(objNewCase.contactId);
                
                if (strAccountID != '')
                {
                    //Account Related Cases
                    if (strRecordType.startsWith('ACT')) 
                        objNewCase.Account_related_Cases__c = strAccountID;
                    
                    //Opportunity Related Cases
                    else if (strRecordType.startsWith('OPT')) 
                        objNewCase.Opportunity_related_Cases__c = strAccountID;
                    
                    //Support Related Cases
                    else if (strRecordType.startsWith('SRV')) 
                    {
                        objNewCase.Support_related_cases__c = strAccountID;
                        
                        //Logic to Populate AutoTask Ticket ID
                        string strSubject = objNewCase.Subject;
                        list<string> lstSubjectWords = new list<string>();
                        system.debug('Case Subject ' + strSubject);
                        
                        if (!String.isEmpty(strSubject))
                        {
                            if (strSubject.contains(' '))
                                lstSubjectWords = strSubject.Split(' ');
                            else
                                lstSubjectWords.add(strSubject);                    
                            
                            for (string strWord : lstSubjectWords)
                            {
                                system.debug('word ' + strWord);
                                String strRegEx = 'T[0-9]{8}(?:.[0-9]{4})';
                                Pattern MyPattern = Pattern.compile(strRegEx);
                                Matcher MyMatcher = MyPattern.matcher(strWord);
                                Boolean result = MyMatcher.find();
                                
                                if(result == true)
                                    objNewCase.AutoTask_Ticket_ID__c = MyMatcher.group(0);
                                
                            }
                            
                        }
                    }
                    
                    //Rollup ChildCases to the parent
                    if (mapParentAcctIds.get(objNewCase.AccountId) != null)
                        objNewCase.Child_Support_related_Cases__c = mapParentAcctIds.get(objNewCase.AccountId);
                    /*else
                        objNewCase.Child_Support_related_Cases__c = mapAccParentAcctIds.get(objNewCase.AccountId);*/
                        
                    
                    if (mapMarketSegments.get(objNewCase.AccountId) != null)
                        objNewCase.Market_Segment__c = mapMarketSegments.get(objNewCase.AccountId);
                    
                   
                }
            }
        }
        catch (exception ex)
        {
            throw new ApexException('Exception:' +ex.getMessage());
            
        }
    }
    /*
    * Name: CreateRecurringCases
    * Description : To create the recurring cases based on the start date, end date and end after
    * Parameters : @lstCase : List of New Cases(trigger.new)
    *              @mapOldcases : Tigger.oldmap
    */
    public static void CreateRecurringCases(list<Case> lstCase, map<id, case> mapOldcases)
    {
 
        try{
            
            list<case> lstcasesInsert = new list<case>();
            Integer iRecurringCount = 0;
            //Filter the record types that are applicable
            list<id> lstRecTypes = getServiceRecordTypes();
            
            for(case objCase : lstCase)
            {   
                integer iweek = 1;
                //Calculating the duration between start date and end date if recurrence is set to true on case
                if(lstRecTypes.Contains(objCase.RecordTypeId) &&  objCase.Recurrence__c == true &&
                   objCase.Frequency__c != null && objCase.Start_Date__c != null && objCase.End_Date__c != null && 
                   (mapOldcases != null && 
                    (objCase.Start_Date__c != mapOldcases.get(objCase.id).Start_Date__c ||
                     objCase.End_Date__c != mapOldcases.get(objCase.id).End_Date__c ||
                     objCase.Frequency__c != mapOldcases.get(objCase.id).Frequency__c)))
                {
                    if (objCase.Frequency__c == 'Daily')
                    {
                        iRecurringCount = objCase.Start_Date__c.daysBetween(objCase.End_Date__c);
                    }else if (objCase.Frequency__c == 'Weekly')
                    {
                        iRecurringCount = objCase.Start_Date__c.daysBetween(objCase.End_Date__c)/7;
                    }else if (objCase.Frequency__c == 'Monthly')
                    {
                        iRecurringCount = objCase.Start_Date__c.monthsBetween(objCase.End_Date__c);
                    }
                    else
                    {// Yearly
                        iRecurringCount = objCase.Start_Date__c.monthsBetween(objCase.End_Date__c)/12;
                    }

                    system.debug('iiRecurringCount---->'+ iRecurringCount);
                    for(integer i=0; i < iRecurringCount; i++)
                    {
                        //Shallow Clone the Case record
                        Case objNewCase = objCase.clone(false,false,false,false); 
                        
                        //Relate the Child cases to the parent case
                        objNewCase.ParentId = objCase.id;
                        
                        //reset the recurrence fields
                        objNewCase.Recurrence__c = false;
                        objNewCase.Start_Date__c = null;
                        objNewCase.End_Date__c = null;
                        objNewCase.Frequency__c = null;
                        lstcasesInsert.add(objNewCase);
                        system.debug('lstcasesInsert---->'+ lstcasesInsert);
                    }
                }
            } 
            if(!lstcasesInsert.isempty())
            {
                //Delete the existing Child Cases
                delete [select id from Case where ParentId in :lstCase];
                
                insert lstcasesInsert;
            }
            system.debug('lstcasesInsert---->'+ lstcasesInsert);
        }
        catch(Exception Ex)
        {
            throw new ApexException('Exception:' +Ex.getMessage());
            
        }
    }
    
    public static void CreateActivityonCase(list<EmailMessage> lstMessages)
    {
        try
        {
            set<id> setRelatedToIds = new set<id>();
            list<EmailMessage> lstNewActivity = new list<EmailMessage>();
            list<EmailMessage> lstEmailMsgs = new list<EmailMessage>();
            for (EmailMessage objMsg : [select ToAddress,ToIds,FromName, FromAddress,HtmlBody,TextBody,Subject,Status,
                                        RelatedToId, BccAddress, ccAddress from EmailMessage where 
                                        id in :lstMessages and Incoming = false])
            {
                string strRelatedToId = objMsg.RelatedToId;
                system.debug('outgoing Message Parent id is ' + strRelatedToId);
                if (!strRelatedToId.startsWith('500'))
                {
                    lstEmailMsgs.add(objMsg);
                    setRelatedToIds.add(objMsg.RelatedToId);
                }
            }
            
            if (setRelatedToIds.size () > 0)
            {
                map<id,id> mapRelatedCases = new map<id, id>();
                for (SFDC_Service_Timecard__c objTimeLog : [select id, Case__c from SFDC_Service_Timecard__c where id in :setRelatedToIds])
                {
                    mapRelatedCases.put(objTimeLog.id, objTimeLog.Case__c);
                }
                
                for (EmailMessage objMsg : lstEmailMsgs)
                {
                    EmailMessage emailMessage = new EmailMessage();
                    emailMessage.status = '3'; // email was sent
                    emailMessage.relatedToId = mapRelatedCases.get(objMsg.RelatedToId); // related to record e.g. an opportunity
                    emailMessage.fromAddress = objMsg.FromAddress; // from address
                    emailMessage.Incoming = false;
                    emailMessage.fromName = objMsg.FromName; // from name
                    emailMessage.subject = objMsg.Subject; // email subject
                    emailMessage.htmlBody = objMsg.HTMLBody; // email body
                    emailMessage.textBody = objMsg.TextBody;
                    emailMessage.CcAddress = objMsg.CcAddress != '' ? objMsg.CcAddress : ''; // CC Address
                    emailMessage.BccAddress = objMsg.BccAddress != '' ? objMsg.BccAddress : ''; //Bcc Address
                    emailMessage.toAddress = objMsg.ToAddress;
                    lstNewActivity.add(emailMessage);
                }
                insert lstNewActivity; // insert
            }
        }
        catch (exception ex)
        {
            system.debug('Exception in CreateActivityonCase :' +ex);
        }
    }
    /*
    * Name: CreateCaseCommentOnEmail
    * Description : To create the Case comment when a new email message is added
    * Parameters : @lstMessages : List of New Email Messages(trigger.new)
    */
    public static void CreateCaseCommentOnEmail(list<EmailMessage> lstMessages)
    {
        system.debug('Createcasecommentonemail');
        string strParentID = '';
        try{
            list<CaseComment> lstNewCaseComments = new list<CaseComment>();
            list<SFDC_Service_Timecard__c> lstTimeCard = new list<SFDC_Service_Timecard__c>();
            //set<id> setCaseID = new set<id>();
            map<id, list<Case>> mapCases = new map<id, list<Case>>();
            boolean bEmailMsg = false;
            User objUser = [select id from User where LastName = 'Email2Case' LIMIT 1];
            
            //Filter the record types that are applicable
            list<id> lstRecTypes = getServiceRecordTypes();
            system.debug('lstrectype' + lstRecTypes);
            list<EmailMessage> lstMessagesFromDB = [select id, Incoming, TextBody, HtmlBody, ParentID, CreatedById, 
                                                    Parent.RecordTypeID, FromAddress from EmailMessage 
                                                    where id in :lstMessages];
            
            system.debug('msg count' + lstMessagesFromDB);
            
            if (lstMessagesFromDB != null && lstMessagesFromDB.size() > 0)
            {
                //Get the list of CaseIds 
                set<id> setCaseIds = new set<id>();
                set<string> setFromEmails = new set<string>(); //Store the set of From Email Address to get the matching Contact Names
                
                for (EmailMessage objMsg : lstMessagesFromDB)
                {
                    if (objMsg.Incoming)
                    {
                        setCaseIds.add(objMsg.ParentID);
                        setFromEmails.add(objMsg.FromAddress);
                    }
                }
                system.debug('setCaseIds ' + setCaseIds);
                
                //Prepare a map of Contacts Name with the respective email address
                map<string, string> mapContactDetails = new map<string, string>();
                for (Contact objCon : [select Name, Email from Contact where Email in :setFromEmails])
                {
                    mapContactDetails.put(objCon.Email, objCon.Name);
                }
                
                //Get the Case Description into a Map
                map<id, Case> mapCaseDescriptions = new map<id, Case>([select id, Contact.Name, Description from Case where id in :setCaseIds]);
                system.debug('mapCaseDescriptions ' + mapCaseDescriptions);
                
                for (EmailMessage objNewMsg : lstMessagesFromDB)
                {
                    //Incoming should be related to Cases only and of Service Record Types only.
                    strParentID = objNewMsg.ParentID;
                    system.debug('Parent Id' + strParentID);
                    system.debug('Parent RectypeId ' + objNewMsg.Parent.RecordTypeId);
                    if (strParentID != null && lstRecTypes !=null)
                    {
                        if (lstRecTypes.Contains(objNewMsg.Parent.RecordTypeId) && objNewMsg.Incoming) //If email is receieved on a Case
                        {
                            system.debug('entered IF');
                            //Create case Comment only if the Case Description is not equals to the EmailMessage TextBody
                            string strMsgBody = '';
                            string strContact = '';
                            if (mapCaseDescriptions.get(strParentID) != null)
                            {
                                strMsgBody = mapCaseDescriptions.get(strParentID).Description;
                                if (mapContactDetails.get(objNewMsg.FromAddress) != null)
                                    strContact = mapContactDetails.get(objNewMsg.FromAddress);
                                
                                //if (mapCaseDescriptions.get(strParentID).Contact.Name !=  null)
                                    //strContact = mapCaseDescriptions.get(strParentID).Contact.Name;
                            }
                            
                            if (objNewMsg.TextBody != strMsgBody)
                            { 
                                SFDC_Service_Timecard__c objTimecard = new SFDC_Service_Timecard__c();
                                Casecomment objNewComment = new Casecomment();
                                objNewComment.ParentId = strParentID; //objNewMsg.ParentID;
                                string strFromAddress = objNewMsg.FromAddress;
                                
                                //It should be private comment if it is a outgoing email message or if the incomign email is from gcibtsticket@gci.com
                                if (objNewMsg.Incoming == false || 
                                    (objNewMsg.Incoming == true && (objNewMsg.FromAddress == 'gcibtsticket@gci.com' || objNewMsg.FromAddress == 'egeddes@gci.com' || strFromAddress.contains('@appshark.com'))))
                                {
                                    objNewComment.isPublished = false; //Outgoing messages do not need to be published as comments.
                                    objTimecard.CommentType__c = 'Case Work';
                                }else
                                {
                                    objNewComment.isPublished = true; 
                                    objTimecard.CommentType__c = 'Email to Case';
                                }
                                
                                string strBody = objNewMsg.HtmlBody;
                                //strBody = strBody.stripHtmlTags();
                                system.debug('strBody----'+strBody);
                                if (strBody !=null && (strBody.contains('From:') || strBody.contains('- Original Message -') || strBody.contains('-Original Message-')
                                                      || (strBody.contains('Progress as of') && strBody.contains('Next Update'))))
                                {
                                    strBody = strBody.substringBefore('From:');
                                    strBody = strBody.substringBefore('- Original Message -');
                                    strBody = strBody.substringBefore('-Original Message-');
                                    //To create case comment from sharepoint template in between (Progress as of & next update)
                                    if(strBody.contains('Progress as of') && strBody.contains('Next Update'))
                                    {
                                        string strProgressAsOf = strBody.substringAfter('Progress as of');
                                        strBody = strProgressAsOf.substringBefore('Next Update');
                                    }
                                }
                                
                                strBody = strBody.substringAfter('</head>');
                                //objTimecard.Comments__c = strBody;
                                //objNewComment.CommentBody= strBody.stripHtmlTags();

                                objNewComment.createdById  = (objUser.ID != null) ? objUser.Id : null;
                                objTimecard.CreatedById = (objUser.ID != null) ? objUser.Id : null;
                                
                                //CommentBody can accept upto 4000 characters only
                                string strCaseComments = strBody.stripHtmlTags();
                                if (strCaseComments.length() > 3500)
                                    strCaseComments = strCaseComments.substring(0, 3500);
                                
                                //If the contact is unknown, pre-pend with the sender (from) email address
                                if (strContact == ''){
                                    objNewComment.CommentBody = 'Comment From ' + objNewMsg.FromAddress + '\n' + strCaseComments;
                                    objTimecard.Service_Note__c = 'Comment From ' + objNewMsg.FromAddress + '\n' + strBody.stripHtmlTags();
                                    objTimecard.Comments__c = 'Comment From ' + objNewMsg.FromAddress + '\n' + strBody;                                       
                                }
                                //If the contact is known, pre-pend with the contact name
                                else{
                                    objNewComment.CommentBody = 'Comment From ' + strContact + '\n' + strCaseComments;
                                    objTimecard.Service_Note__c = 'Comment From ' + strContact + '\n' + strBody.stripHtmlTags();
                                    objTimecard.Comments__c = 'Comment From ' + strContact + '\n' + strBody;
                                }
                                /*else // Commented as part of User Story 298 - Outgoing do not need any prepending
                                {
                                    objNewComment.CommentBody = 'Comment From ' + UserInfo.getName() + '\n' + strBody;                            
                                }*/
                                objTimecard.Date_of_Service__c = system.today();
                                objTimecard.Hours_Worked__c = '0';
                                objTimecard.Case__c = strParentID;
                                //lstNewCaseComments.add(objNewComment); 
                                //lstTimeCard.add(objTimecard);
                                //
                                Insert objNewComment;
                                objTimeCard.CaseCommentID__c = objNewComment.Id;
                                Insert objTimecard;
                            }
                               
                        }
                    }
                }
                //system.debug('lstNew Comments' + lstNewCaseComments);
                
                //Database.DMLOptions dlo = new Database.DMLOptions();
                //dlo.AllowFieldTruncation = true;
                //dlo.EmailHeader.triggerAutoResponseEmail = true;
                
                //if (lstNewCaseComments.size() > 0)
                //{
                   // Database.insert(lstNewCaseComments, dlo);
                    //insert lstNewCaseComments;
                //}
            }
        
            
        }
        catch(Exception Ex)
        {
            //Send a notification to the user and partial save the transaction
            SendErrNotification('Error while inserting a Case Comment for the case id '+ strParentID + ' ' + Ex.getMessage());
            //throw new ApexException('Exception:' +Ex.getMessage());
            
            
        }
    }
    

    /*
    * Name: PrependTechNameOnCaseComment
    * Description : To prepend Case comment with technician name in comment body
    * Parameters : @lstCaseComments : List of Case Comments(trigger.new)
    */
    public static void PrependTechNameOnCaseComment(list<CaseComment> lstCaseComments)
    {
        if(lstCaseComments != null && lstCaseComments.size()>0){
            for (CaseComment objNewComment : lstCaseComments)
            {
                string strCommentBody = objNewComment.CommentBody;
                if (!strCommentBody.contains('Comment From '))
                    objNewComment.CommentBody = 'Comment From ' + UserInfo.getName() + '\n' + objNewComment.CommentBody;   
            }
        }
    }
    
    /*
    * Name: getServiceRecordTypes
    * Description : To get service recordtypes which starts with SRV
    */
    public static list<id> getServiceRecordTypes()
    {
        //Filter the record types that are applicable
        list<id> lstRecTypes = new list<id>();
        for (Recordtype objRecType : [Select id From RecordType where sobjecttype = 'Case' and 
                                      DeveloperName Like 'SRV%'])
        {
            lstRecTypes.add(objRecType.id);
        }
        return lstRecTypes;
    }
    
    
    /*
    * Name: DeleteDuplicateCases
    * Description : To delete duplicate cases which has auto task id pattern in subject or body
    * Parameters : @lstNewCases : List of New Cases(trigger.new)
    */
    public static void DeleteDuplicateCases (list<Case> lstCases)
    {
        try
        {
            set<Id> setDeleteCases = new set<Id>();
            set<string> setAutoTaskId = new set<string>();
            map<string, id> mapTicketIds = new map<string, id>();
            
            //Check the cases if the subject has autotaskticketid
            for (Case objCase : lstCases)
            {
                string strSubject = objCase.Subject;
                
                list<string> lstSubjectWords = new list<string>();
                if (strSubject != null)
                {
                    if (strSubject.contains(' '))
                        lstSubjectWords = strSubject.Split(' ');
                    else
                        lstSubjectWords.add(strSubject);
                    
                    system.debug(' '+lstSubjectWords);
                    for (string strWord : lstSubjectWords)
                    {
                        String strRegEx = 'T[0-9]{8}(?:.[0-9]{4})';
                        Pattern MyPattern = Pattern.compile(strRegEx);
                        Matcher MyMatcher = MyPattern.matcher(strWord);
                        Boolean result = MyMatcher.find();

                        //system.debug(result + MyMatcher.group(0));
                        if(result == true)
                        {
                            if(MyMatcher.group(0) != null)
                            {
                                setAutoTaskId.add(MyMatcher.group(0)); //Set of Auto Task Ticket IDs
                                setDeleteCases.add(objCase.Id); //Set of Case IDs
                                mapTicketIds.put(MyMatcher.group(0), objCase.Id);
                            }
                            system.debug('matching for deletion');
                        }
                    }
                }
            }
            
            list<case> lstExistingCase = new list<Case>([select Id, Autotask_Ticket_ID__c from 
                                                         case where Autotask_Ticket_ID__c In : setAutoTaskId
                                                        and id not in :lstCases]); //Exclude the cases in context
            for (Case objCase : lstExistingCase)
            {
                //if there is no existing ticket for the same autotaskticketid, then remove it from the set
                if (!setAutoTaskId.Contains(objCase.Autotask_Ticket_ID__c))
                    setDeleteCases.remove(mapTicketIds.get(objCase.Autotask_Ticket_ID__c));
            }
            
            if (lstExistingCase.size() == 0)
                setDeleteCases.clear();
            
            system.debug('Cases for Deletion' + setDeleteCases);
            
            if (setDeleteCases.size() > 0)
                delete [select id from Case where id in :setDeleteCases];
        }catch (exception ex)
        {
            throw new ApexException('Exception Deleting the Duplicate Cases:' +ex.getMessage());
        }
    }
    
    /*
    * Name: AddEmailMessageToAutoTaskCases
    * Description : To add email messages to the existing autotask cases if the auto task id exists in subject or body
    * Parameters : @lstNewCases : List of New Email Messages(trigger.new)
    */
    public static void AddEmailMessageToAutoTaskCases(list<EmailMessage> lstMsgs)
    {
        try{
            set<string> setAutoTaskId = new set<String>();
            Map<string,string> mapCaseId = new map<string,string>();
            
            //To validate if the subject contains Autotask Id in this pattern(T12345678.1234)
            for(EmailMessage objMsg : lstMsgs)
            {
                string strSubject = objMsg.Subject;
                list<string> lstSubjectWords = new list<string>();
                
                if (!String.isEmpty(strSubject))
                {
                    if (strSubject.contains(' '))
                        lstSubjectWords = strSubject.Split(' ');
                    else
                        lstSubjectWords.add(strSubject);                    
                    
                    for (string strWord : lstSubjectWords)
                    {
                        String strRegEx = 'T[0-9]{8}(?:.[0-9]{4})';
                        Pattern MyPattern = Pattern.compile(strRegEx);
                        Matcher MyMatcher = MyPattern.matcher(strWord);
                        Boolean result = MyMatcher.find();
                        
                        if(result == true)
                            setAutoTaskId.add(MyMatcher.group(0));
                            
                    }
                    
                }
                
            }
            
            if (!setAutoTaskId.isEmpty() && setAutoTaskId.size() > 0)
            {
                //Getting Case Id for the existing Autotask Ticket
                for(Case objCase : [select Id, AutoTask_Ticket_ID__c from case where AutoTask_Ticket_ID__c IN : setAutoTaskId])
                {
                    mapCaseId.put(objCase.AutoTask_Ticket_ID__c, objCase.Id);
                }
                system.debug('mapCaseId----'+mapCaseId);
                
            }
            //To include thread id in the subject and map the correct case id to Email Message
            for(EmailMessage objEM : lstMsgs)
            {  
                string strSubject = objEM.Subject;
                list<string> lstSubjectWords = new list<string>();
                
                if (strSubject != null)
                {
                    if (strSubject.contains(' '))
                        lstSubjectWords = strSubject.Split(' ');
                    else
                        lstSubjectWords.add(strSubject);
                    
                    for (string strWord : lstSubjectWords)
                    {
                        String strRegEx = 'T[0-9]{8}(?:.[0-9]{4})';
                        Pattern MyPattern = Pattern.compile(strRegEx);
                        Matcher MyMatcher = MyPattern.matcher(strWord);
                        Boolean result = MyMatcher.find();
                        
                        //system.debug(result + MyMatcher.group(0));
                        if(result == true)
                        {
                            if (mapCaseId.get(MyMatcher.group(0)) != null)
                            {
                                string strCaseID = mapCaseId.get(MyMatcher.group(0));
                                string strThreadId = getThreadId(strCaseID);
                                objEM.Subject = objEM.Subject + ' - ' + strThreadId;
                                objEm.ParentId = strCaseID;
                                objEm.HtmlBody = objEm.HtmlBody + ' ' + strThreadId;
                            }
                            
                        }
                    }       
                }   
            }
        }
        catch(exception ex)
        {
            throw new ApexException('Exception:' +ex.getMessage() + ex.getLineNumber());
        }
    }
    
    /*
    * Name: getThreadId
    * Description : To form threadid 
    * Parameters : @caseId : Id of a case
    */
    public static String getThreadId(String caseId){
        return '[ ref:_' + UserInfo.getOrganizationId().left(15) + '._' + caseId.left(15) +':ref ]';
     
    }
    
    /*
    * Name: getThreadId
    * Description : Notify GCI Support if any exception occurs
    * Parameters : @ErrorDesc : Error description
    */
    public static void SendErrNotification(string ErrorDesc)
    {        
        try{
            list<string> lstDistribution = new list<String>();
            
            //Query on Email template 
           //Retrieve custom settings
            OrgWideEmailAddress objOrgAddress = [select DisplayName, Address from OrgWideEmailAddress where DisplayName = 'GCI BTS Support'];
            
            Messaging.singleEmailMessage Emailwithattch = new Messaging.singleEmailMessage();
            lstDistribution.add('giribabu.yerra@appshark.com');
            Emailwithattch.setToAddresses(lstDistribution);
            Emailwithattch.setSenderDisplayName('GCI Support');
            Emailwithattch.setReplyTo(objOrgAddress.Address);
            Emailwithattch.setPlainTextBody(ErrorDesc);
            Messaging.SingleEmailMessage[] messages = 
                new List<Messaging.SingleEmailMessage> {Emailwithattch};
                    Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
            
        }
        Catch(exception ex)
        {
            throw new ApexException('Exception:' +ex.getMessage());
        }
    }
    /*
* Name: SendCaseCommentNotification
* Description : Sends notification to the receipients listed in custom setting if the case status is changed/Time log is created
* Parameters : @lstCases : List of Case Id's /List of Time log ID's
*              @NotificationType : Email template for Time Log creation /Case Status updation
*/
    public static void SendCaseNotification(list<Case> lstCases, map<id, case> mapOldCase) {
        try{
            //Notifications on Case
            list<Messaging.SingleEmailMessage> lstNotifications= new list<Messaging.SingleEmailMessage>();
            
            //list of Cases that failed sending Notifications due to the max number of recipients in BCC
            list<Case> lstFailedCases = new list<Case>();
            
            //Query on Email template 
            map<string ,ID> mapEmailTemplate = new map<string,ID>();
            for(EmailTemplate em : [select id,DeveloperName from EmailTemplate where DeveloperName like 'SRV%'])
            {
                mapEmailTemplate.put(em.DeveloperName,em.ID);
            }
            
            //Get the list of OrgEMail Addresses
            map<string, OrgWideEmailAddress> mapOrgWideEmails = new map<String, OrgWideEmailAddress>();
            for (OrgWideEmailAddress objOrgAddress : [select Id, DisplayName, Address from OrgWideEmailAddress])
            { 
                mapOrgWideEmails.put(objOrgAddress.DisplayName, objOrgAddress);
            }
            
            //Get the Userid of Email2Case User
            string strEmail2CaseID ='';
            User objUser = [select id from User where alias='emai'];
            if (objUser !=null)
                strEmail2CaseID = objUser.Id;
            
            //Describe call to get the custom setting feild labels
            String strobjectName='SRV_Notification_Config__c';
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            Schema.SObjectType CustomsettingSchema = schemaMap.get(strobjectName);
            Map<String, Schema.SObjectField> fieldMap = CustomsettingSchema.getDescribe().fields.getMap();
            
            Map<String, SRV_Notification_Config__c> MapNotifConfig = SRV_Notification_Config__c.getAll();
            Map<String, SRV_Email_To_Case_Config__c> MapEmailToCaseConfig = SRV_Email_To_Case_Config__c.getAll();
            
            //Loop thru the list of Cases
            for (Case objCase : lstCases)
            {
                //Continue sending notification only when case status is changed not for any other updates on case.
                string strOldCaseStatus = '';
                if (mapOldCase !=null)
                    strOldCaseStatus = mapOldCase.get(objCase.Id).Status;
                //Based on Case Status, get the Template and Recipients List from map of Custom Settings
                SRV_Notification_Config__c NotificationConfigs = SRV_Notification_Config__c.getValues(objCase.Status);
                
                system.debug('Case Status ' + objCase.Status + objCase.CreatedBy.Alias + strOldCaseStatus);
                //Only if there is configuration defined for this case status in custom settings
                if (NotificationConfigs != null && 
                    (//Skip it for email to case cases
                        (objCase.Status != 'To Do' && objCase.Status != strOldCaseStatus) || 
                        (objCase.Status == 'To Do' && strOldCaseStatus == '' && objCase.CreatedById != strEmail2CaseID) 
                    ))
                    {
                    //RecordType applicable from Custom setting - Blank means all record types
                    string strRecType = NotificationConfigs.Record_Type__c; 
                    string strCaseRecType = objCase.Record_Type_Name__c;
                    
                    system.debug('Notification rectype ' + strRecType);
                    system.debug('Case rec Type ' + strCaseRecType);
                    //Proceed only if the notifications are enabled and it is valid for the current record type
                    if (NotificationConfigs.Disable_Notification__c == false && 
                        (strRecType == null || 
                         (strRecType != null && strCaseRecType != null && strRecType.contains(strCaseRecType))
                        ))
                    {
                        
                        //Get the Recipients List by Market Segment --CHANGE
                        String strRecipientsList = ''; //= NotificationConfigs.Recipients__c;
                        String strTORecipientsList = '';
                        String strBCCRecipientsList = '';
                        //system.debug('objCase.Market_Segment_HDN__c---'+objCase.Market_Segment_HDN__c);
                        //assigning recipients based on market segment
                        for (String fieldName: fieldMap.keySet()) {// list of all field API name;
                            //To check Market segment on timelog is same as Notification config field label
                            string CaseMarketSegment = objCase.Market_Segment__c;
                            string fieldlabel = fieldMap.get(fieldName).getDescribe().getLabel();
                            
                            //To check Market segment on timelog is same as Notification config field label
                            if(fieldlabel.startsWith(CaseMarketSegment))
                            {
                                SRV_Notification_Config__c value = MapNotifConfig.get(objCase.Status);
                                strRecipientsList = (string)value.get(fieldName);
                                system.debug('fieldName--'+fieldName+ '---string)value.get(fieldName)----'+(string)value.get(fieldName));
                                if(fieldlabel.endsWith('To'))
                                    strTORecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                                else if(fieldlabel.endsWith('BCC'))
                                    strBCCRecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                                
                                //if contactEmail is a recipient, Throw an exception if the contact email was bounced earlier.  
                                
                                if (strTORecipientsList.contains('ContactEmail') )            
                                {
                                    system.debug('Case Contact is' + objCase.ContactEmail);
                                    if(objCase.ContactId == null || objCase.ContactEmail == null)
                                    {
                                        throw new ApexException('Case has no contact or Email populated.');
                                    }
                                    else if(objCase.Contact.EmailBouncedDate != null)
                                    {
                                        throw new ApexException('Contact Email is Bounced');
                                    }
                                }
                            }
                        }
                        system.debug('strTORecipientsList---'+strTORecipientsList);
                        system.debug('strBCCRecipientsList---'+strBCCRecipientsList);
                        
                        //Proceed preparing email only if there are recipients
                        if (strBCCRecipientsList.length() > 0 || strTORecipientsList.length() >0)
                        {
                            //Adding To addresses to list                        
                            list<string> lstTODistribution = new list<string>();
                            if(strTORecipientsList != '')
                                lstTODistribution = ConvertRecipientsToList(strTORecipientsList, objCase);
                            system.debug('lstTODistribution---'+lstTODistribution);
                            
                            //Adding Bcc addresses to List
                            list<string> lstBCCDistribution = new list<string>();
                            if(strBCCRecipientsList != '')
                                lstBCCDistribution = ConvertRecipientsToList(strBCCRecipientsList, objCase);
                            system.debug('lstBCCDistribution--1-'+lstBCCDistribution);
                            
                            //Prepare the EmailInstance (modified to render data for vf email template)
                            Messaging.singleEmailMessage objEmailMsg = Messaging.renderStoredEmailTemplate(mapEmailTemplate.get(NotificationConfigs.Template_Name__c), userinfo.getUserId(), objCase.Id);
                            
                            //Check if the count of recipients is more than 25, as BCC can accept only 25
                            if ((!lstTODistribution.isempty())
                                || (!lstBCCDistribution.isempty() && lstBCCDistribution.size() <= 25))
                            {
                                objEmailMsg.setToAddresses(lstTODistribution);
                                if(lstBCCDistribution.size() <= 25)
                                    objEmailMsg.setBccAddresses(lstBCCDistribution);
                                //Emailwithattch.setSenderDisplayName('GCI Support');
                                if(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c) != null)
                                    objEmailMsg.setOrgWideEmailAddressId(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c).ID);
                                //if(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c) != null)
                                //objEmailMsg.setReplyTo(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c).Address);
                                
                                //Assigns Reply To email from custom setting based on the support team
                                string strSupportTeam = objCase.SRV_Support_Team__c;
                                if (strSupportTeam != '' && !MapEmailToCaseConfig.isempty())
                                {
                                    if (strSupportTeam.startsWith('BTS') && MapEmailToCaseConfig.get('BTS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('BTS').Reply_To_Email__c);
                                    else if (strSupportTeam.startsWith('IS') && MapEmailToCaseConfig.get('IS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('IS').Reply_To_Email__c);
                                    else if(strSupportTeam.startsWith('RMS') && MapEmailToCaseConfig.get('RMS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('RMS').Reply_To_Email__c);
                                }
                                String emailSubject = objEmailMsg.getSubject();
                                String emailTextBody = objEmailMsg.getPlainTextBody();
                                String emailHTMLBody = objEmailMsg.getHtmlBody();
                                system.debug('emailHTMLBody--'+emailHTMLBody);
                                objEmailMsg.setSubject(emailSubject);
                                objEmailMsg.setPlainTextBody(emailTextBody);
                                objEmailMsg.setHtmlBody(emailHTMLBody);
                                
                                //commented objEmailMsg.setWhatId(objTimeLog.Id); 
                                objEmailMsg.setSaveAsActivity(True);
                                //objEmailMsg.setTreatTargetObjectAsRecipient(false);
                                //if(objCase.ContactId != null)
                                objEmailMsg.setTargetObjectId(objCase.ContactId);
                                //objEmailMsg.setTargetObjectId('0031g00000GMBeHAAX');
                                //commented objEmailMsg.setTemplateId(mapEmailTemplate.get(NotificationConfigs.Template_Name__c));
                                //Add it to the list
                                lstNotifications.add(objEmailMsg);
                            }else
                            { 
                                //Mark a flag on the timeLog that the message was not sent.
                                Case objFailedCase = new Case(id = objCase.Id);
                                objFailedCase.Notification_Failed__c = true;
                                lstFailedCases.add(objFailedCase);
                                
                            }
                        }
                        else
                        {
                            system.debug('Exception in SendCaseNotifications : No Recipients configured for this case status ' + objCase.Status);
                        }
                    }
                }else
                {
                    system.debug('Exception in SendCaseNotifications : No custom setting for the Case Status '+ objCase.Status);
                }
                
            }
            
            //Send Emails
            if (lstNotifications.size() >0)
            {
                Messaging.SendEmailResult [] EmailResult = Messaging.sendEmail(lstNotifications);
                system.debug('EmailResult---'+EmailResult);
                for(Messaging.SendEmailResult objResult : EmailResult)
                {
                    if(objResult.isSuccess()){}
                    else{
                        system.debug('Email Errors--'+objResult.getErrors());
                    }
                }
            }
            
            //Update the Cases that failed notifications
            if (lstFailedCases.size() > 0)
                update lstFailedCases;
        }
        Catch(exception ex)
        {
            system.debug('Exception in SendCaseNotifications :' + ex + ' at ' + ex.getLineNumber());
            throw new ApexException('Exception:' +ex.getMessage());
        }
    }
    
    //To split recipients list by comma and email fields 
    public static list<string> ConvertRecipientsToList(string RecipientList,Case objCase)
    {
        list<string> lstDistribution = new list<string>();
        list<id> lstUserIDs = new list<id>();
        //Prepare Recipients List into a List
            for (string strRecipientField : RecipientList.split(','))
        {
            String strDistributionList;
            //Recipient will be either a FieldName, Email Address
            //Add the logic to check the email address by finding @ -- CHANGE
            system.debug('strRecipientField---'+strRecipientField);
            //Check if it is an email address
            if(strRecipientField.contains('@'))
            {
                lstDistribution.add(strRecipientField);
            }else
            {
                //Get the value of recipient field value from TimeLog
                strDistributionList =  (String) objCase.get(strRecipientField.trim()) != '' ? (String) objCase.get(strRecipientField.trim()) : '';                                
            }
            
            if (strDistributionList!= null)
            {
                if (strDistributionList.startsWith('005')) //if it is a user
                {
                    lstUserIDs.add(strDistributionList);
                }else if (strDistributionList.contains(';'))
                    lstDistribution.addall(strDistributionList.split(';'));
                else
                    lstDistribution.addall(strDistributionList.split(','));
                
                system.debug('lstDistribution---'+lstDistribution+'---strDistributionList---'+strDistributionList);
            }
        }
         if (lstUserIDs.size() > 0)
             lstDistribution.addAll(lstUserIDs);
        return lstDistribution;
    }
    
     /*
     * Name: SendTimeLogNotification
     * Description : Sends notification to the receipients listed in custom setting if the case status is changed/Time log is created
     * Parameters : @lstCases : List of Case Id's /List of Time log ID's
     *              @NotificationType : Email template for Time Log creation /Case Status updation
     */
    /*@InvocableMethod(label='Send TimeLog Notifications')
    public static void SendTimeLogNotification(list<SFDC_Service_Timecard__c> lstTimeLogs) {
        try{
            //Notifications on Case
            list<Messaging.SingleEmailMessage> lstNotifications= new list<Messaging.SingleEmailMessage>();
            
            //list of TimeLogs that failed sending Notifications due to the max number of recipients in BCC
            list<SFDC_Service_Timecard__c> lstFailedLogs = new list<SFDC_Service_Timecard__c>();
            
            //Query on Email template 
            map<string ,ID> mapEmailTemplate = new map<string,ID>();
            for(EmailTemplate em : [select id,DeveloperName from EmailTemplate where DeveloperName like 'SRV%'])
            {
                mapEmailTemplate.put(em.DeveloperName,em.ID);
            }
            
            //Get the list of OrgEMail Addresses
            map<string, OrgWideEmailAddress> mapOrgWideEmails = new map<String, OrgWideEmailAddress>();
            for (OrgWideEmailAddress objOrgAddress : [select Id, DisplayName, Address from OrgWideEmailAddress])
            {
                mapOrgWideEmails.put(objOrgAddress.DisplayName, objOrgAddress);
            }
            
            //Describe call to get the custom setting feild labels
            String strobjectName='SRV_Notification_Config__c';
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            Schema.SObjectType CustomsettingSchema = schemaMap.get(strobjectName);
            Map<String, Schema.SObjectField> fieldMap = CustomsettingSchema.getDescribe().fields.getMap();
            
            Map<String, SRV_Notification_Config__c> MapNotifConfig = SRV_Notification_Config__c.getAll();
            Map<String, SRV_Email_To_Case_Config__c> MapEmailToCaseConfig = SRV_Email_To_Case_Config__c.getAll();
            system.debug('MapEmailToCaseConfig---'+MapEmailToCaseConfig);
            
            //Loop thru the list of Cases
            for (SFDC_Service_Timecard__c objTimeLog : lstTimeLogs)
            {
                system.debug('--objTimeLog---'+objTimeLog);
                //system.debug('objTimeLog.ContactID----'+objTimeLog.ContactID__c+'----objTimeLog.Case__r.contact.email----'+objTimeLog.Case__r.contact.email+'-----'+objTimeLog.Case_Contact_Email__c);
                if(objTimeLog.ContactID__c != null && objTimeLog.Case_Contact_Email__c != null)
                {
                    //Based on Case Status, get the Template and Recipients List from map of Custom Settings
                    SRV_Notification_Config__c NotificationConfigs = SRV_Notification_Config__c.getValues(objTimeLog.CommentType__c);
                    
                    //Only if there is configuration defined for this case status in custom settings
                    if (NotificationConfigs != null && NotificationConfigs.Disable_Notification__c == false)
                    {
                        //Get the Recipients List by Market Segment --CHANGE
                        String strRecipientsList = ''; //= NotificationConfigs.Recipients__c;
                        String strTORecipientsList = '';
                        String strBCCRecipientsList = '';
                        //assigning recipients based on market segment
                        for (String fieldName: fieldMap.keySet()) {// list of all field API name;
                            string timelogMarketSegment = objTimeLog.Market_Segment__c;
                            string fieldlabel = fieldMap.get(fieldName).getDescribe().getLabel();
                            
                            //To check Market segment on timelog is same as Notification config field label
                            if(fieldlabel.startsWith(timelogMarketSegment))
                            {
                                SRV_Notification_Config__c value = MapNotifConfig.get(objTimeLog.CommentType__c);
                                system.debug('fieldlabel----'+fieldlabel+'---fieldName--'+fieldName+ '---string)value.get(fieldName)----'+(string)value.get(fieldName));
                                if(fieldlabel.endsWith('To'))
                                    strTORecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                                else if(fieldlabel.endsWith('BCC'))
                                    strBCCRecipientsList = ((string)value.get(fieldName) !=null) ?(string)value.get(fieldName) : '';
                            }
                        }
                        system.debug('strTORecipientsList---'+strTORecipientsList);
                        system.debug('strBCCRecipientsList---'+strBCCRecipientsList);
                        
                        //Proceed preparing email only if there are recipients
                        if ((strBCCRecipientsList !='' && strBCCRecipientsList.length() > 0) || 
                            (strTORecipientsList != '' && strTORecipientsList.length() >0))
                        {
                            //Adding To addresses to list                        
                            list<string> lstTODistribution = new list<string>();
                            if(strTORecipientsList != '')
                                lstTODistribution = ConvertRecipientsToList(strTORecipientsList, objTimeLog);
                            system.debug('lstTODistribution---'+lstTODistribution);
                            
                            //Adding Bcc addresses to List
                            list<string> lstBCCDistribution = new list<string>();
                            if(strBCCRecipientsList != '')
                                lstBCCDistribution = ConvertRecipientsToList(strBCCRecipientsList, objTimeLog);
                            system.debug('lstBCCDistribution--1-'+lstBCCDistribution);
                            //Prepare the EmailInstance (modified to render data for vf email template)
                            Messaging.singleEmailMessage objEmailMsg = Messaging.renderStoredEmailTemplate(mapEmailTemplate.get(NotificationConfigs.Template_Name__c), UserInfo.getUserId(), objTimeLog.Id);
                            
                            //Check if the count of recipients is more than 25, as BCC can accept only 25
                            if ((!lstTODistribution.isempty())
                                || (!lstBCCDistribution.isempty() && lstBCCDistribution.size() <= 25))
                            {
                                objEmailMsg.setToAddresses(lstTODistribution);
                                if(lstBCCDistribution.size() <= 25)
                                    objEmailMsg.setBccAddresses(lstBCCDistribution);
                                
                                //Emailwithattch.setSenderDisplayName('GCI Support');
                                if(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c) != null)
                                    objEmailMsg.setOrgWideEmailAddressId(mapOrgWideEmails.get(NotificationConfigs.FromEmail__c).ID);
                                //if(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c) != null)
//objEmailMsg.setReplyTo(mapOrgWideEmails.get(NotificationConfigs.ReplyToEmail__c).Address);
                                
                                //Assigns Reply To email from custom setting based on the support team
                                string strSupportTeam = objTimeLog.Support_Team__c;
                                if (strSupportTeam != '' && !MapEmailToCaseConfig.isempty())
                                {
                                    if (strSupportTeam.startsWith('BTS') && MapEmailToCaseConfig.get('BTS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('BTS').Reply_To_Email__c);
                                    else if (strSupportTeam.startsWith('IS') && MapEmailToCaseConfig.get('IS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('IS').Reply_To_Email__c);
                                    else if(strSupportTeam.startsWith('RMS') && MapEmailToCaseConfig.get('RMS') != null)
                                        objEmailMsg.setReplyTo(MapEmailToCaseConfig.get('RMS').Reply_To_Email__c);
                                }
                                String emailSubject = objEmailMsg.getSubject();
                                String emailTextBody = objEmailMsg.getPlainTextBody();
                                String emailHTMLBody = objEmailMsg.getHtmlBody();
                                system.debug('emailHTMLBody--'+emailHTMLBody);
                                objEmailMsg.setSubject(emailSubject);
                                objEmailMsg.setPlainTextBody(emailTextBody);
                                objEmailMsg.setHtmlBody(emailHTMLBody);
                                
                                //commented objEmailMsg.setWhatId(objTimeLog.Id); 
                                objEmailMsg.setSaveAsActivity(True);
                                objEmailMsg.setTreatTargetObjectAsRecipient(false);
                                //if(objCase.ContactId != null)
                                //objEmailMsg.setTargetObjectId(objTimeLog.ContactID__c);
                                //objEmailMsg.setTargetObjectId('0031g00000GMBeHAAX');
                                //commented objEmailMsg.setTemplateId(mapEmailTemplate.get(NotificationConfigs.Template_Name__c));
                                //Add it to the list
                                lstNotifications.add(objEmailMsg);
                            }else
                            {
                                //Mark a flag on the timeLog that the message was not sent.
                                SFDC_Service_Timecard__c objFailedLog = new SFDC_Service_Timecard__c(id = objTimeLog.Id);
                                objFailedLog.Notification_Failed__c = true;
                                lstFailedLogs.add(objFailedLog);
                            }
                        }
                        else
                        {
                            system.debug('Exception in SendTimeLogNotification : No Recipients configured for this Case Comment Type ' + objTimeLog.CommentType__c);
                        }
                    }else
                    {
                        system.debug('Exception in SendTimeLogNotification : No custom setting for Case Comment Type '+ objTimeLog.CommentType__c);
                    }
                }
                else{
                    throw new AuraHandledException('Exception:Notifications cannot be sent until the Case Contact is corrected');
                }
                if(objTimeLog.ContactID__c != null && objTimeLog.Case_Contact_Bounced_Date__c != null)
                {
                    throw new AuraHandledException('Exception: Contact Email is Bounced');
                }
            }
            
            //Send Emails
            if (lstNotifications.size() >0)
            {
                Messaging.SendEmailResult [] EmailResult = Messaging.sendEmail(lstNotifications);
                system.debug('EmailResult---'+EmailResult);
                for(Messaging.SendEmailResult objResult : EmailResult)
                {
                    system.debug('Email result errors ' + objResult.errors);
                    if(objResult.isSuccess()){}
                    else{
                        system.debug('Email Errors--'+objResult.getErrors());
                        for(SFDC_Service_Timecard__c objTime : lstTimeLogs)
                        {
                            //Mark a flag on the timeLog that the message was not sent.
                            SFDC_Service_Timecard__c objFailedLog = new SFDC_Service_Timecard__c(id = objTime.Id);
                            objFailedLog.Notification_Failed__c = true;
                            objFailedLog.Notification_Sent_Date__c = system.today();
                            lstFailedLogs.add(objFailedLog);
                        }
                    }
                }
            }
            
            //Update the timelogs that failed notifications
            if (lstFailedLogs.size() > 0)
                update lstFailedLogs;
        }
        Catch(ContactException ex)
        {
            system.debug('Exception in SendTimeLogNotification :' + ex + ' at ' + ex.getLineNumber());
            //throw new AuraHandledException('Exception:' +ex.getMessage());
        }
        
    }*/
    
    //To split recipients list by comma and email fields 
    /*public static list<string> ConvertRecipientsToList(string RecipientList,SFDC_Service_Timecard__c objTimeLog)
    {
        list<string> lstDistribution = new list<string>();
        list<id> lstUserIDs = new list<id>();
        //Prepare Recipients List into a List
            for (string strRecipientField : RecipientList.split(','))
        {
            String strDistributionList;
            //Recipient will be either a FieldName, Email Address
            //Add the logic to check the email address by finding @ -- CHANGE
            system.debug('strRecipientField---'+strRecipientField);
            //Check if it is an email address
            if(strRecipientField.contains('@'))
            {
                lstDistribution.add(strRecipientField);
            }else
            {
                //Get the value of recipient field value from TimeLog
                strDistributionList =  (String) objTimeLog.get(strRecipientField.trim()) != '' ? (String) objTimeLog.get(strRecipientField.trim()) : '';                                
            }
            
            if (strDistributionList!= null)
            {
                if (strDistributionList.startsWith('005')) //if it is a user
                {
                    lstUserIDs.add(strDistributionList);
                }else if (strDistributionList.contains(';'))
                    lstDistribution.addall(strDistributionList.split(';'));
                else
                    lstDistribution.addall(strDistributionList.split(','));
                
                system.debug('lstDistribution---'+lstDistribution+'---strDistributionList---'+strDistributionList);
            }
        }
         if (lstUserIDs.size() > 0)
             lstDistribution.addAll(lstUserIDs);
        return lstDistribution;
    }*/
    
   public static void capture_Timezone_Service_Event(list<Case> srvCases)
    {
    
    
     List<SRV_Service_Event__c> srv_time = new List<SRV_Service_Event__c>();
     SRV_Service_Event__c time_strut = new SRV_Service_Event__c();
     String time_user = string.valueOf(UserInfo.getTimeZone());
     String timezName;
     
     Schema.DescribeFieldResult timeResult = User.TimeZoneSidKey.getdescribe();
        List<Schema.PicklistEntry> ple = timeResult.getPicklistValues();
            for(Schema.PicklistEntry p : ple)
            {
                if(string.valueOf(time_user) == string.valueOf(p.getValue()))
               {
                timezName = p.getLabel();
                break;
                }
             
            }
             
      if(timezName!=null)
      time_strut.Event_Time_Zone__c=timezName;
      
     
     for(Case cs: srvCases){

     
     for(SRV_Service_Event__c s_time : [select Case__r.id, Event_time_zone__c, Event_End__c from SRV_Service_Event__c where Case__c = :cs.Id])
         {
     time_strut.id = s_time.id;
     srv_time.add(time_strut);
 
         }
     }
     if(srv_time.size()>0)
     update srv_time;
     }
    
    public class ApexException extends Exception {}
    public class ContactException extends Exception {}
    public class ContactBouncedException extends Exception {}

}